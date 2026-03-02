#!/usr/bin/env bash
# =============================================================================
# decision-os / 26p: TSエラー修正 + ポート3008再起動
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

FRONTEND="$HOME/projects/decision-os/frontend/src"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
nvm use 20 2>/dev/null || true

# ---------- 1. App.tsx: 不要import削除 ----------
section "1. App.tsx 修正"
cat > "$FRONTEND/App.tsx" << 'TSX'
import { Routes, Route, Navigate } from 'react-router-dom'
import Layout from '@/components/Layout'
import Dashboard from '@/pages/Dashboard'
import IssueList from '@/pages/IssueList'
import IssueDetail from '@/pages/IssueDetail'
import InputNew from '@/pages/InputNew'
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
        <Route path="users" element={<UserManagement />} />
      </Route>
    </Routes>
  )
}
TSX
success "App.tsx 修正完了"

# ---------- 2. IssueList.tsx: 未使用型 StatusKey 削除 ----------
section "2. IssueList.tsx 修正"
cat > "$FRONTEND/pages/IssueList.tsx" << 'TSX'
import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { Plus, Search, Filter, ChevronDown, AlertCircle, Loader2 } from 'lucide-react'
import apiClient from '@/api/client'

interface Issue {
  id: string
  title: string
  status: string
  priority?: number
  issue_type?: string
  created_at: string
  labels?: { name: string; color?: string }[]
}

const STATUS_STYLE: Record<string, { bg: string; color: string; label: string }> = {
  open:        { bg: 'rgba(59,130,246,0.15)',  color: '#60a5fa', label: 'Open' },
  in_progress: { bg: 'rgba(245,158,11,0.15)',  color: '#fbbf24', label: 'In Progress' },
  doing:       { bg: 'rgba(245,158,11,0.15)',  color: '#fbbf24', label: 'Doing' },
  done:        { bg: 'rgba(34,197,94,0.15)',   color: '#4ade80', label: 'Done' },
  closed:      { bg: 'rgba(100,116,139,0.15)', color: '#94a3b8', label: 'Closed' },
}

const PRIORITY_COLOR: Record<number, string> = {
  1: '#ef4444', 2: '#f97316', 3: '#eab308', 4: '#22c55e', 5: '#64748b',
}

async function fetchIssues(params: Record<string, string>) {
  const query = new URLSearchParams(params).toString()
  const res = await apiClient.get(`/issues?${query}`)
  const data = res.data
  // APIが { items: [], total: N } 形式または [] 形式に対応
  if (Array.isArray(data)) return { items: data as Issue[], total: (data as Issue[]).length }
  if (Array.isArray(data?.items)) return { items: data.items as Issue[], total: (data.total ?? data.items.length) as number }
  if (Array.isArray(data?.issues)) return { items: data.issues as Issue[], total: (data.total ?? data.issues.length) as number }
  const arr = Object.values(data as Record<string, unknown>).find((v): v is Issue[] => Array.isArray(v))
  return { items: arr ?? [], total: arr?.length ?? 0 }
}

const STATUSES = [
  { value: '', label: 'すべて' },
  { value: 'open', label: 'Open' },
  { value: 'in_progress', label: 'In Progress' },
  { value: 'done', label: 'Done' },
  { value: 'closed', label: 'Closed' },
]

export default function IssueList() {
  const [search, setSearch] = useState('')
  const [status, setStatus] = useState('')
  const [page, setPage] = useState(1)
  const limit = 20

  const params: Record<string, string> = {
    skip: String((page - 1) * limit),
    limit: String(limit),
    ...(search ? { q: search } : {}),
    ...(status ? { status } : {}),
  }

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['issues', params],
    queryFn: () => fetchIssues(params),
    placeholderData: (prev) => prev,
  })

  const issues: Issue[] = data?.items ?? []
  const total: number = data?.total ?? 0
  const totalPages = Math.ceil(total / limit)

  return (
    <div>
      {/* Header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 24 }}>
        <div>
          <h1 style={{ margin: 0, fontSize: 22, fontWeight: 700, color: '#f1f5f9', letterSpacing: '-0.03em' }}>
            課題一覧
          </h1>
          <p style={{ margin: '4px 0 0', fontSize: 13, color: '#64748b' }}>
            {total.toLocaleString()} 件
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
          <Plus size={15} />
          要望を登録
        </Link>
      </div>

      {/* Filters */}
      <div className="card" style={{ padding: '14px 16px', marginBottom: 16, display: 'flex', gap: 10, alignItems: 'center', flexWrap: 'wrap' }}>
        <div style={{ position: 'relative', flex: 1, minWidth: 200 }}>
          <Search size={14} style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)', color: '#64748b' }} />
          <input
            value={search}
            onChange={e => { setSearch(e.target.value); setPage(1) }}
            placeholder="課題を検索..."
            style={{
              width: '100%', padding: '8px 10px 8px 32px',
              background: '#0f1117', border: '1px solid #2d3548',
              borderRadius: 6, color: '#e2e8f0', fontSize: 13,
              outline: 'none',
            }}
          />
        </div>

        <div style={{ position: 'relative' }}>
          <Filter size={13} style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)', color: '#64748b' }} />
          <select
            value={status}
            onChange={e => { setStatus(e.target.value); setPage(1) }}
            style={{
              padding: '8px 32px 8px 30px',
              background: '#0f1117', border: '1px solid #2d3548',
              borderRadius: 6, color: '#e2e8f0', fontSize: 13,
              outline: 'none', cursor: 'pointer', appearance: 'none',
            }}
          >
            {STATUSES.map(s => <option key={s.value} value={s.value}>{s.label}</option>)}
          </select>
          <ChevronDown size={12} style={{ position: 'absolute', right: 10, top: '50%', transform: 'translateY(-50%)', color: '#64748b', pointerEvents: 'none' }} />
        </div>
      </div>

      {/* Table */}
      <div className="card" style={{ overflow: 'hidden' }}>
        {isLoading ? (
          <div style={{ padding: '60px', textAlign: 'center', color: '#64748b' }}>
            <Loader2 size={24} style={{ margin: '0 auto 12px', display: 'block', animation: 'spin 1s linear infinite' }} />
            <style>{`@keyframes spin { to { transform: rotate(360deg) } }`}</style>
            読み込み中...
          </div>
        ) : isError ? (
          <div style={{ padding: '40px', textAlign: 'center', color: '#ef4444' }}>
            <AlertCircle size={24} style={{ margin: '0 auto 8px', display: 'block' }} />
            {(error as Error)?.message ?? 'エラーが発生しました'}
          </div>
        ) : issues.length === 0 ? (
          <div style={{ padding: '60px', textAlign: 'center', color: '#64748b', fontSize: 14 }}>
            課題が見つかりません
          </div>
        ) : (
          <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
            <thead>
              <tr style={{ borderBottom: '1px solid #1e2535' }}>
                {['タイトル', 'ステータス', 'タイプ', '優先度', '作成日'].map(h => (
                  <th key={h} style={{
                    padding: '10px 16px', textAlign: 'left',
                    color: '#64748b', fontWeight: 600, fontSize: 11,
                    letterSpacing: '0.08em', textTransform: 'uppercase',
                  }}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {issues.map((issue, i) => {
                const st = STATUS_STYLE[issue.status] ?? STATUS_STYLE['open']
                return (
                  <tr
                    key={issue.id}
                    style={{
                      borderBottom: i < issues.length - 1 ? '1px solid #1a2030' : 'none',
                      transition: 'background 0.1s',
                    }}
                    onMouseEnter={e => (e.currentTarget.style.background = 'rgba(255,255,255,0.025)')}
                    onMouseLeave={e => (e.currentTarget.style.background = 'transparent')}
                  >
                    <td style={{ padding: '12px 16px', maxWidth: 360 }}>
                      <Link
                        to={`/issues/${issue.id}`}
                        style={{ color: '#e2e8f0', textDecoration: 'none', fontWeight: 500, lineHeight: 1.4, display: 'block' }}
                        onMouseEnter={e => (e.currentTarget.style.color = '#818cf8')}
                        onMouseLeave={e => (e.currentTarget.style.color = '#e2e8f0')}
                      >
                        {issue.title}
                      </Link>
                      {issue.labels && issue.labels.length > 0 && (
                        <div style={{ display: 'flex', gap: 4, marginTop: 4, flexWrap: 'wrap' }}>
                          {issue.labels.map(lb => (
                            <span key={lb.name} className="badge" style={{
                              background: lb.color ? `${lb.color}22` : 'rgba(99,102,241,0.15)',
                              color: lb.color ?? '#818cf8',
                            }}>{lb.name}</span>
                          ))}
                        </div>
                      )}
                    </td>
                    <td style={{ padding: '12px 16px' }}>
                      <span className="badge" style={{ background: st.bg, color: st.color }}>
                        {st.label}
                      </span>
                    </td>
                    <td style={{ padding: '12px 16px', color: '#94a3b8' }}>
                      {issue.issue_type ?? '—'}
                    </td>
                    <td style={{ padding: '12px 16px' }}>
                      {issue.priority != null ? (
                        <span style={{
                          display: 'inline-flex', alignItems: 'center', gap: 4,
                          color: PRIORITY_COLOR[issue.priority] ?? '#94a3b8',
                          fontFamily: 'DM Mono, monospace', fontSize: 12,
                        }}>
                          {'●'} P{issue.priority}
                        </span>
                      ) : '—'}
                    </td>
                    <td style={{ padding: '12px 16px', color: '#64748b', fontFamily: 'DM Mono, monospace', fontSize: 11 }}>
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
          <button
            onClick={() => setPage(p => Math.max(1, p - 1))}
            disabled={page === 1}
            style={{
              padding: '6px 14px', borderRadius: 6, fontSize: 13,
              background: '#1a1f2e', border: '1px solid #2d3548',
              color: page === 1 ? '#334155' : '#94a3b8', cursor: page === 1 ? 'not-allowed' : 'pointer',
            }}
          >←</button>
          <span style={{ padding: '6px 14px', fontSize: 13, color: '#64748b' }}>
            {page} / {totalPages}
          </span>
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
success "IssueList.tsx 修正完了"

# ---------- 3. 型チェック再確認 ----------
section "3. 型チェック"
cd "$HOME/projects/decision-os/frontend"
npm run typecheck && echo -e "${GREEN}[OK]    型チェック PASS${RESET}" || echo -e "${YELLOW}[WARN]  型警告あり（続行）${RESET}"

# ---------- 4. ポート3008のプロセスをkillして再起動 ----------
section "4. ポート3008 再起動"

# 既存プロセスをkill
PID=$(lsof -ti :3008 2>/dev/null || true)
if [ -n "$PID" ]; then
  echo "ポート3008のプロセス(PID: $PID)を停止..."
  kill "$PID" 2>/dev/null || true
  sleep 2
fi

cd "$HOME/projects/decision-os/frontend"
nohup npm run dev -- --host 0.0.0.0 --port 3008 > "$HOME/projects/decision-os/logs/frontend.log" 2>&1 &
sleep 3

# 起動確認
if curl -s -o /dev/null -w "%{http_code}" http://localhost:3008 | grep -q "^[23]"; then
  echo -e "${GREEN}[OK]    フロントエンド起動確認: http://localhost:3008${RESET}"
else
  # Viteはルートに200返さない場合もあるのでプロセス確認
  if lsof -ti :3008 &>/dev/null; then
    echo -e "${GREEN}[OK]    フロントエンド起動中: http://localhost:3008${RESET}"
  else
    echo -e "${YELLOW}[WARN]  起動確認できませんでした。ログ: tail -f ~/projects/decision-os/logs/frontend.log${RESET}"
  fi
fi

echo ""
echo -e "${GREEN}✔ 完了！ブラウザで http://localhost:3008 を開いてください${RESET}"
echo -e "  ログ確認: tail -f ~/projects/decision-os/logs/frontend.log"
