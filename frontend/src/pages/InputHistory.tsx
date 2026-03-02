import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { FileText, Search, ChevronDown, Loader2, AlertCircle, Mail, Mic, Users, Bug, MoreHorizontal, ArrowRight } from 'lucide-react'
import apiClient from '@/api/client'

interface InputRecord {
  id: string
  source_type: string
  raw_text: string
  author?: string
  author_name?: string
  created_at: string
  item_count?: number
  issue_count?: number
}

const SOURCE_META: Record<string, { icon: React.ElementType; label: string; color: string; bg: string }> = {
  email:   { icon: Mail,           label: 'メール',   color: '#3b82f6', bg: 'rgba(59,130,246,0.1)'  },
  voice:   { icon: Mic,            label: '音声',     color: '#8b5cf6', bg: 'rgba(139,92,246,0.1)'  },
  meeting: { icon: Users,          label: '会議',     color: '#10b981', bg: 'rgba(16,185,129,0.1)'  },
  bug:     { icon: Bug,            label: 'バグ報告', color: '#ef4444', bg: 'rgba(239,68,68,0.1)'   },
  other:   { icon: MoreHorizontal, label: 'その他',   color: '#6366f1', bg: 'rgba(99,102,241,0.1)'  },
}
const SOURCE_FILTERS = [
  { value: '', label: 'すべて' }, { value: 'email', label: 'メール' },
  { value: 'voice', label: '音声' }, { value: 'meeting', label: '会議' },
  { value: 'bug', label: 'バグ報告' }, { value: 'other', label: 'その他' },
]

async function fetchInputs(params: Record<string, string>) {
  const res = await apiClient.get(`/inputs?${new URLSearchParams(params)}`)
  const d = res.data
  if (Array.isArray(d)) return { items: d as InputRecord[], total: d.length }
  if (Array.isArray(d?.items)) return { items: d.items as InputRecord[], total: (d.total ?? d.items.length) as number }
  const arr = Object.values(d as Record<string, unknown>).find((v): v is InputRecord[] => Array.isArray(v))
  return { items: arr ?? [], total: arr?.length ?? 0 }
}

export default function InputHistory() {
  const [search, setSearch] = useState('')
  const [sourceFilter, setSourceFilter] = useState('')
  const [page, setPage] = useState(1)
  const limit = 20
  const params: Record<string, string> = {
    skip: String((page - 1) * limit), limit: String(limit),
    ...(search ? { q: search } : {}), ...(sourceFilter ? { source_type: sourceFilter } : {}),
  }
  const { data, isLoading, isError } = useQuery({
    queryKey: ['inputs', params], queryFn: () => fetchInputs(params), placeholderData: p => p,
  })
  const inputs = data?.items ?? []
  const total = data?.total ?? 0
  const totalPages = Math.ceil(total / limit)

  return (
    <div style={{ animation: 'fadeIn 0.2s ease' }}>
      {/* Header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 24 }}>
        <div>
          <h1 style={{ fontSize: 22, fontWeight: 800, color: 'var(--text-primary)', letterSpacing: '-0.03em' }}>
            要望履歴
          </h1>
          <p style={{ marginTop: 4, fontSize: 13, color: 'var(--text-muted)' }}>
            登録済みの原文・解析履歴 — {total.toLocaleString()} 件
          </p>
        </div>
        <Link to="/inputs/new" style={{
          display: 'inline-flex', alignItems: 'center', gap: 6, padding: '9px 18px',
          background: 'var(--accent)', borderRadius: 9, color: '#fff',
          textDecoration: 'none', fontSize: 13, fontWeight: 600,
          boxShadow: 'var(--shadow-btn)', transition: 'opacity 0.15s',
        }}
        onMouseEnter={e => (e.currentTarget.style.opacity = '0.88')}
        onMouseLeave={e => (e.currentTarget.style.opacity = '1')}
        >
          <FileText size={14} /> 新規登録
        </Link>
      </div>

      {/* Filters */}
      <div className="card" style={{ padding: '12px 14px', marginBottom: 14, display: 'flex', gap: 10, flexWrap: 'wrap' }}>
        <div style={{ position: 'relative', flex: 1, minWidth: 220 }}>
          <Search size={14} style={{ position: 'absolute', left: 11, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)', pointerEvents: 'none' }} />
          <input
            value={search} onChange={e => { setSearch(e.target.value); setPage(1) }}
            placeholder="原文テキスト・著者で検索..."
            style={{ width: '100%', padding: '8px 12px 8px 34px' }}
          />
        </div>
        <div style={{ position: 'relative' }}>
          <select value={sourceFilter} onChange={e => { setSourceFilter(e.target.value); setPage(1) }}
            style={{ padding: '8px 32px 8px 12px', minWidth: 110 }}>
            {SOURCE_FILTERS.map(s => <option key={s.value} value={s.value}>{s.label}</option>)}
          </select>
          <ChevronDown size={13} style={{ position: 'absolute', right: 9, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)', pointerEvents: 'none' }} />
        </div>
      </div>

      {/* List */}
      {isLoading ? (
        <div className="card" style={{ padding: '60px', textAlign: 'center', color: 'var(--text-muted)' }}>
          <Loader2 size={22} style={{ margin: '0 auto 10px', display: 'block', animation: 'spin 1s linear infinite' }} />
          読み込み中...
        </div>
      ) : isError ? (
        <div className="card" style={{ padding: '40px', textAlign: 'center', color: '#dc2626' }}>
          <AlertCircle size={20} style={{ marginBottom: 8, display: 'block', margin: '0 auto 8px' }} />
          データの取得に失敗しました
        </div>
      ) : inputs.length === 0 ? (
        <div className="card" style={{ padding: '60px', textAlign: 'center', color: 'var(--text-muted)', fontSize: 14 }}>
          要望履歴がありません
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          {inputs.map(inp => {
            const src = SOURCE_META[inp.source_type] ?? SOURCE_META['other']
            const SrcIcon = src.icon
            const preview = inp.raw_text?.length > 140 ? inp.raw_text.slice(0, 140) + '…' : inp.raw_text

            return (
              <Link key={inp.id} to={`/inputs/${inp.id}`} style={{ textDecoration: 'none' }}>
                <div className="card" style={{ padding: '16px 20px', transition: 'box-shadow 0.15s, border-color 0.15s' }}
                  onMouseEnter={e => {
                    const el = e.currentTarget as HTMLDivElement
                    el.style.borderColor = 'var(--accent)'
                    el.style.boxShadow = '0 0 0 3px var(--accent-light)'
                  }}
                  onMouseLeave={e => {
                    const el = e.currentTarget as HTMLDivElement
                    el.style.borderColor = 'var(--border)'
                    el.style.boxShadow = 'var(--shadow-sm)'
                  }}
                >
                  <div style={{ display: 'flex', gap: 14, alignItems: 'flex-start' }}>
                    <div style={{
                      width: 38, height: 38, borderRadius: 10, flexShrink: 0,
                      background: src.bg, display: 'flex', alignItems: 'center', justifyContent: 'center',
                      border: `1px solid ${src.color}30`,
                    }}>
                      <SrcIcon size={17} color={src.color} />
                    </div>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 7, flexWrap: 'wrap' }}>
                        <span className="badge" style={{ background: src.bg, color: src.color }}>{src.label}</span>
                        {(inp.author_name ?? inp.author) && (
                          <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>
                            by {inp.author_name ?? inp.author}
                          </span>
                        )}
                        <span style={{ marginLeft: 'auto', fontSize: 11, color: 'var(--text-muted)', fontFamily: 'DM Mono, monospace' }}>
                          {new Date(inp.created_at).toLocaleString('ja-JP', { year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' })}
                        </span>
                      </div>
                      <p style={{ fontSize: 13, color: 'var(--text-secondary)', lineHeight: 1.65, whiteSpace: 'pre-wrap', marginBottom: 8 }}>
                        {preview}
                      </p>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
                        {inp.item_count != null && (
                          <span style={{ fontSize: 11, color: 'var(--text-muted)' }}>
                            分解: <strong style={{ color: 'var(--text-secondary)' }}>{inp.item_count}</strong> ITEM
                          </span>
                        )}
                        {inp.issue_count != null && inp.issue_count > 0 && (
                          <span style={{ fontSize: 11, color: 'var(--text-muted)' }}>
                            課題: <strong style={{ color: 'var(--accent)' }}>{inp.issue_count}</strong> 件
                          </span>
                        )}
                        <span style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 4, fontSize: 12, color: 'var(--accent)', fontWeight: 500 }}>
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
      )}

      {/* Pagination */}
      {totalPages > 1 && (
        <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', gap: 6, marginTop: 20 }}>
          <button onClick={() => setPage(p => Math.max(1, p - 1))} disabled={page === 1}
            style={{ padding: '6px 14px', borderRadius: 7, fontSize: 13, background: 'var(--bg-surface)', border: '1px solid var(--border)', color: page === 1 ? 'var(--border)' : 'var(--text-secondary)', cursor: page === 1 ? 'not-allowed' : 'pointer' }}>←</button>
          <span style={{ fontSize: 13, color: 'var(--text-muted)', padding: '0 8px' }}>{page} / {totalPages}</span>
          <button onClick={() => setPage(p => Math.min(totalPages, p + 1))} disabled={page === totalPages}
            style={{ padding: '6px 14px', borderRadius: 7, fontSize: 13, background: 'var(--bg-surface)', border: '1px solid var(--border)', color: page === totalPages ? 'var(--border)' : 'var(--text-secondary)', cursor: page === totalPages ? 'not-allowed' : 'pointer' }}>→</button>
        </div>
      )}
    </div>
  )
}
