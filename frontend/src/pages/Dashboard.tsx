import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { ArrowRight, Inbox, Zap, AlertCircle, TrendingUp } from 'lucide-react'
import apiClient from '@/api/client'

interface DashboardStats {
  unprocessed_inputs?: number
  pending_action_items?: number
  open_issues?: number
  total_inputs?: number
  total_issues?: number
}

async function fetchStats(): Promise<DashboardStats> {
  const res = await apiClient.get('/dashboard/stats').catch(() => ({ data: {} }))
  return res.data ?? {}
}

async function fetchCounts(): Promise<DashboardStats> {
  const res = await apiClient.get('/dashboard/counts').catch(() => ({ data: {} }))
  return res.data ?? {}
}

async function fetchRecentIssues() {
  const res = await apiClient.get('/issues?limit=5&skip=0')
  const d = res.data
  if (Array.isArray(d)) return d
  if (Array.isArray(d?.items)) return d.items
  return []
}

const STATUS_STYLE: Record<string, { bg: string; color: string; label: string }> = {
  open:        { bg: 'var(--status-open-bg)',   color: 'var(--status-open-fg)',   label: 'open' },
  in_progress: { bg: 'var(--status-prog-bg)',   color: 'var(--status-prog-fg)',   label: 'in_progress' },
  doing:       { bg: 'var(--status-prog-bg)',   color: 'var(--status-prog-fg)',   label: 'doing' },
  done:        { bg: 'var(--status-done-bg)',   color: 'var(--status-done-fg)',   label: 'done' },
  closed:      { bg: 'var(--status-closed-bg)', color: 'var(--status-closed-fg)', label: 'closed' },
}

export default function Dashboard() {
  const { data: stats1 } = useQuery({ queryKey: ['stats'], queryFn: fetchStats })
  const { data: stats2 } = useQuery({ queryKey: ['counts'], queryFn: fetchCounts })
  const stats = { ...stats2, ...stats1 }
  const { data: recent = [] } = useQuery({ queryKey: ['recent-issues'], queryFn: fetchRecentIssues })

  const CARDS = [
    { label: '未処理 INPUT',    value: stats.unprocessed_inputs  ?? 0, sub: `総数 ${stats.total_inputs ?? 0}件`,  icon: Inbox,        accent: '#3b82f6' },
    { label: 'ACTION待ち ITEM', value: stats.pending_action_items ?? 0, sub: '要判断',                            icon: Zap,          accent: '#8b5cf6' },
    { label: '未完了 ISSUE',    value: stats.open_issues          ?? 0, sub: `総数 ${stats.total_issues ?? 0}件`, icon: AlertCircle,  accent: '#ec4899' },
  ]

  return (
    <div>
      {/* Header */}
      <div style={{ marginBottom: 28 }}>
        <h1 style={{ margin: 0, fontSize: 22, fontWeight: 800, color: 'var(--text-primary)', letterSpacing: '-0.03em' }}>
          ダッシュボード
        </h1>
        <p style={{ margin: '4px 0 0', fontSize: 13, color: 'var(--text-muted)' }}>
          {new Date().toLocaleDateString('ja-JP', { year: 'numeric', month: 'long', day: 'numeric', weekday: 'short' })}
        </p>
      </div>

      {/* Stats cards */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3,1fr)', gap: 16, marginBottom: 24 }}>
        {CARDS.map(({ label, value, sub, icon: Icon, accent }) => (
          <div key={label} className="card" style={{ padding: '22px 24px', position: 'relative', overflow: 'hidden' }}>
            <div style={{
              position: 'absolute', top: 0, right: 0, width: 80, height: 80,
              background: `${accent}14`, borderRadius: '0 12px 0 80px',
            }} />
            <div style={{
              width: 38, height: 38, borderRadius: 10,
              background: `${accent}14`,
              display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 14,
              border: `1px solid ${accent}22`,
            }}>
              <Icon size={18} color={accent} />
            </div>
            <div style={{ fontSize: 34, fontWeight: 800, color: accent, letterSpacing: '-0.04em', lineHeight: 1 }}>
              {value.toLocaleString()}
            </div>
            <div style={{ marginTop: 6, fontSize: 12, color: 'var(--text-secondary)', fontWeight: 600 }}>{label}</div>
            <div style={{ marginTop: 2, fontSize: 11, color: 'var(--text-muted)', fontFamily: 'DM Mono, monospace' }}>{sub}</div>
          </div>
        ))}
      </div>

      {/* Recent Issues */}
      <div className="card" style={{ overflow: 'hidden' }}>
        <div style={{
          padding: '14px 20px', borderBottom: '1px solid var(--border)',
          display: 'flex', justifyContent: 'space-between', alignItems: 'center',
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <TrendingUp size={15} color="var(--accent)" />
            <span style={{ fontWeight: 700, fontSize: 14, color: 'var(--text-primary)' }}>直近の課題</span>
          </div>
          <Link to="/issues" style={{ display: 'flex', alignItems: 'center', gap: 4, color: 'var(--accent)', textDecoration: 'none', fontSize: 12, fontWeight: 500 }}>
            すべて見る <ArrowRight size={12} />
          </Link>
        </div>

        {recent.length === 0 ? (
          <div style={{ padding: '40px', textAlign: 'center', color: 'var(--text-muted)', fontSize: 13 }}>
            課題はまだありません
          </div>
        ) : recent.map((issue: { id: string; title: string; status: string }, i: number) => {
          const st = STATUS_STYLE[issue.status] ?? STATUS_STYLE['open']
          return (
            <Link
              key={issue.id}
              to={`/issues/${issue.id}`}
              style={{
                display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                padding: '12px 20px', textDecoration: 'none',
                borderBottom: i < recent.length - 1 ? '1px solid var(--border)' : 'none',
                transition: 'background 0.1s',
              }}
              onMouseEnter={e => (e.currentTarget.style.background = 'var(--bg-hover)')}
              onMouseLeave={e => (e.currentTarget.style.background = 'transparent')}
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <div style={{ width: 6, height: 6, borderRadius: '50%', background: st.color, flexShrink: 0 }} />
                <span style={{ color: 'var(--text-primary)', fontSize: 13, fontWeight: 500 }}>{issue.title}</span>
              </div>
              <span className="badge" style={{ background: st.bg, color: st.color }}>{st.label}</span>
            </Link>
          )
        })}
      </div>
    </div>
  )
}
