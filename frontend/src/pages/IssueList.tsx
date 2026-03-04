import PageHeader from '../components/PageHeader';
import { useState } from 'react'
import { useCurrentProject } from '../hooks/useCurrentProject'
import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { Plus, Search, Filter, ChevronDown, AlertCircle, Loader2 } from 'lucide-react'
import apiClient from '@/api/client'


interface Issue {
  id: string; title: string; status: string
  priority?: number; issue_type?: string; created_at: string
  labels?: any[]
}

async function fetchIssues(params: Record<string, string>) {
  const res = await apiClient.get(`/issues?${new URLSearchParams(params)}`)
  const d = res.data
  if (Array.isArray(d)) return { items: d as Issue[], total: d.length }
  if (Array.isArray(d?.issues)) return { items: d.issues as Issue[], total: (d.total ?? d.issues.length) as number }
  if (Array.isArray(d?.items)) return { items: d.items as Issue[], total: (d.total ?? d.items.length) as number }
  const arr = Object.values(d as Record<string, unknown>).find((v): v is Issue[] => Array.isArray(v))
  return { items: arr ?? [], total: arr?.length ?? 0 }
}

const STATUS_STYLE: Record<string, { bg: string; color: string; label: string }> = {
  open:        { bg: 'var(--status-open-bg)',   color: 'var(--status-open-fg)',   label: 'Open' },
  in_progress: { bg: 'var(--status-prog-bg)',   color: 'var(--status-prog-fg)',   label: 'In Progress' },
  doing:       { bg: 'var(--status-prog-bg)',   color: 'var(--status-prog-fg)',   label: 'Doing' },
  done:        { bg: 'var(--status-done-bg)',   color: 'var(--status-done-fg)',   label: 'Done' },
  closed:      { bg: 'var(--status-closed-bg)', color: 'var(--status-closed-fg)', label: 'Closed' },
}

const PRIORITY_COLOR: Record<number, string> = { 1: '#ef4444', 2: '#f97316', 3: '#eab308', 4: '#22c55e', 5: '#94a3b8' }
const STATUSES = [
  { value: '', label: 'すべて' }, { value: 'open', label: 'Open' },
  { value: 'in_progress', label: 'In Progress' }, { value: 'done', label: 'Done' }, { value: 'closed', label: 'Closed' },
]
export default function IssueList() {
  const { projectId } = useCurrentProject()
  const [search, setSearch] = useState('')
  const [status, setStatus] = useState('')
  const [page, setPage] = useState(1)
  const limit = 20
  const params: Record<string, string> = {
    skip: String((page - 1) * limit), limit: String(limit),
    ...(search ? { q: search } : {}), ...(status ? { status } : {}),
    ...(projectId ? { project_id: projectId } : {}),
  }
  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['issues', params, projectId], queryFn: () => fetchIssues(params), placeholderData: p => p,
  })
  const issues = data?.items ?? []
  const total = data?.total ?? 0
  const totalPages = Math.ceil(total / limit)

  const filterStyle: React.CSSProperties = {
    padding: '8px 12px', background: 'var(--bg-input)',
    border: '1px solid var(--border)', borderRadius: 8,
    color: 'var(--text-primary)', fontSize: 13, outline: 'none',
  }

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 24 }}>
        <div>
          <PageHeader title="課題一覧" />
          <p style={{ margin: '4px 0 0', fontSize: 13, color: 'var(--text-muted)' }}>{total.toLocaleString()} 件</p>
        </div>
        <Link to="/inputs/new" style={{
          display: 'inline-flex', alignItems: 'center', gap: 6, padding: '9px 16px', borderRadius: 8,
          background: 'linear-gradient(135deg, #6366f1, #8b5cf6)', color: '#fff',
          textDecoration: 'none', fontSize: 13, fontWeight: 600,
          boxShadow: '0 4px 12px var(--accent-glow)',
        }}>
          <Plus size={14} /> 要望を登録
        </Link>
      </div>

      {/* Filters */}
      <div className="card" style={{ padding: '12px 16px', marginBottom: 16, display: 'flex', gap: 10, alignItems: 'center', flexWrap: 'wrap' }}>
        <div style={{ position: 'relative', flex: 1, minWidth: 200 }}>
          <Search size={14} style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
          <input
            value={search} onChange={e => { setSearch(e.target.value); setPage(1) }}
            placeholder="課題を検索..."
            style={{ ...filterStyle, width: '100%', paddingLeft: 32 }}
          />
        </div>
        <div style={{ position: 'relative' }}>
          <Filter size={13} style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
          <select value={status} onChange={e => { setStatus(e.target.value); setPage(1) }}
            style={{ ...filterStyle, paddingLeft: 30, paddingRight: 28, appearance: 'none', cursor: 'pointer' }}>
            {STATUSES.map(s => <option key={s.value} value={s.value}>{s.label}</option>)}
          </select>
          <ChevronDown size={12} style={{ position: 'absolute', right: 8, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)', pointerEvents: 'none' }} />
        </div>
      </div>

      {/* Table */}
      <div className="card" style={{ overflow: 'hidden' }}>
        {isLoading ? (
          <div style={{ padding: '60px', textAlign: 'center', color: 'var(--text-muted)' }}>
            <Loader2 size={22} style={{ margin: '0 auto 10px', display: 'block', animation: 'spin 1s linear infinite' }} />
            <style>{`@keyframes spin{to{transform:rotate(360deg)}}`}</style>
            読み込み中...
          </div>
        ) : isError ? (
          <div style={{ padding: '40px', textAlign: 'center', color: '#dc2626' }}>
            <AlertCircle size={20} style={{ marginBottom: 8, display: 'block', margin: '0 auto 8px' }} />
            {(error as Error)?.message ?? 'エラーが発生しました'}
          </div>
        ) : issues.length === 0 ? (
          <div style={{ padding: '60px', textAlign: 'center', color: 'var(--text-muted)', fontSize: 14 }}>
            課題が見つかりません
          </div>
        ) : (
          <table style={{ width: '100%', fontSize: 13 }}>
            <thead>
              <tr style={{ borderBottom: '1px solid var(--border)', background: 'var(--bg-input)' }}>
                {['タイトル', 'ステータス', 'タイプ', '優先度', '作成日'].map(h => (
                  <th key={h} style={{
                    padding: '10px 16px', textAlign: 'left', color: 'var(--text-muted)',
                    fontWeight: 600, fontSize: 11, letterSpacing: '0.07em', textTransform: 'uppercase',
                  }}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {issues.map((issue, i) => {
                const st = STATUS_STYLE[issue.status] ?? STATUS_STYLE['open']
                return (
                  <tr key={issue.id}
                    style={{ borderBottom: i < issues.length - 1 ? '1px solid var(--border)' : 'none', transition: 'background 0.1s' }}
                    onMouseEnter={e => (e.currentTarget.style.background = 'var(--bg-hover)')}
                    onMouseLeave={e => (e.currentTarget.style.background = 'transparent')}
                  >
                    <td style={{ padding: '12px 16px', maxWidth: 380 }}>
                      <Link to={`/issues/${issue.id}`} style={{ color: 'var(--text-primary)', textDecoration: 'none', fontWeight: 500, display: 'block' }}
                        onMouseEnter={e => (e.currentTarget.style.color = 'var(--accent)')}
                        onMouseLeave={e => (e.currentTarget.style.color = 'var(--text-primary)')}
                      >{issue.title}</Link>
                      {issue.labels && (issue.labels?.length ?? 0) > 0 && (
                        <div style={{ display: 'flex', gap: 4, marginTop: 4 }}>
                          {issue.labels?.map(lb => (
                            <span key={lb.name} className="badge" style={{
                              background: lb.color ? `${lb.color}22` : 'var(--accent-light)',
                              color: lb.color ?? 'var(--accent)',
                            }}>{lb.name}</span>
                          ))}
                        </div>
                      )}
                    </td>
                    <td style={{ padding: '12px 16px' }}>
                      <span className="badge" style={{ background: st.bg, color: st.color }}>{st.label}</span>
                    </td>
                    <td style={{ padding: '12px 16px', color: 'var(--text-secondary)' }}>{issue.issue_type ?? '—'}</td>
                    <td style={{ padding: '12px 16px' }}>
                      {issue.priority != null
                        ? <span style={{ color: PRIORITY_COLOR[issue.priority] ?? 'var(--text-muted)', fontFamily: 'DM Mono, monospace', fontSize: 12 }}>● P{issue.priority}</span>
                        : '—'}
                    </td>
                    <td style={{ padding: '12px 16px', color: 'var(--text-muted)', fontFamily: 'DM Mono, monospace', fontSize: 11 }}>
                      {new Date(issue.created_at).toLocaleDateString('ja-JP', { month: '2-digit', day: '2-digit' })}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        )}
      </div>

      {/* Pagination */}
      {totalPages > 1 && (
        <div style={{ display: 'flex', justifyContent: 'center', gap: 6, marginTop: 20 }}>
          {[
            { label: '←', onClick: () => setPage(p => Math.max(1, p - 1)), disabled: page === 1 },
            { label: '→', onClick: () => setPage(p => Math.min(totalPages, p + 1)), disabled: page === totalPages },
          ].map((btn, i) => (
            <button key={i} onClick={btn.onClick} disabled={btn.disabled} style={{
              padding: '6px 14px', borderRadius: 6, fontSize: 13,
              background: 'var(--bg-surface)', border: '1px solid var(--border)',
              color: btn.disabled ? 'var(--border)' : 'var(--text-secondary)',
              cursor: btn.disabled ? 'not-allowed' : 'pointer',
            }}>{btn.label}</button>
          ))}
          <span style={{ padding: '6px 14px', fontSize: 13, color: 'var(--text-muted)' }}>{page} / {totalPages}</span>
        </div>
      )}
    </div>
  )
}
