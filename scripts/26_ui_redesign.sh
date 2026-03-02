#!/usr/bin/env bash
# =============================================================================
# decision-os / Step 26: UIリデザイン + IssueList バグ修正
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; exit 1; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
FRONTEND="$PROJECT_DIR/frontend/src"

[[ -d "$PROJECT_DIR" ]] || error "プロジェクトが見つかりません: $PROJECT_DIR"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
nvm use 20 2>/dev/null || true

# ---------- 1. Tailwind CSS + lucide-react 追加 ----------
section "1. 依存パッケージ追加"
cd "$PROJECT_DIR/frontend"

npm install tailwindcss @tailwindcss/vite lucide-react 2>/dev/null || \
  npm install tailwindcss lucide-react

# tailwind vite plugin があれば使う、なければ postcss
if node -e "require('@tailwindcss/vite')" 2>/dev/null; then
  cat > vite.config.ts << 'VITE'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import path from 'path'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: { alias: { '@': path.resolve(__dirname, './src') } },
  server: {
    port: 3008,
    host: '0.0.0.0',
    proxy: {
      '/api': { target: 'http://localhost:8089', changeOrigin: true },
      '/ws':  { target: 'ws://localhost:8089', ws: true },
    },
  },
})
VITE
else
  npm install -D tailwindcss postcss autoprefixer
  npx tailwindcss init -p 2>/dev/null || true
  cat > tailwind.config.js << 'TW'
/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: { extend: {} },
  plugins: [],
}
TW
  cat > vite.config.ts << 'VITE'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  resolve: { alias: { '@': path.resolve(__dirname, './src') } },
  server: {
    port: 3008,
    host: '0.0.0.0',
    proxy: {
      '/api': { target: 'http://localhost:8089', changeOrigin: true },
      '/ws':  { target: 'ws://localhost:8089', ws: true },
    },
  },
})
VITE
fi

success "依存パッケージ追加完了"

# ---------- 2. グローバル CSS ----------
section "2. グローバルCSS"
cat > "$FRONTEND/index.css" << 'CSS'
@import url('https://fonts.googleapis.com/css2?family=DM+Sans:ital,opsz,wght@0,9..40,300;0,9..40,400;0,9..40,500;0,9..40,600;1,9..40,400&family=DM+Mono:wght@400;500&display=swap');

@tailwind base;
@tailwind components;
@tailwind utilities;

:root {
  --sidebar-w: 240px;
  --sidebar-collapsed-w: 64px;
}

*, *::before, *::after { box-sizing: border-box; }

body {
  font-family: 'DM Sans', sans-serif;
  background: #0f1117;
  color: #e2e8f0;
  margin: 0;
}

.sidebar {
  width: var(--sidebar-w);
  transition: width 0.25s cubic-bezier(0.4, 0, 0.2, 1);
}
.sidebar.collapsed {
  width: var(--sidebar-collapsed-w);
}
.sidebar-label {
  transition: opacity 0.2s, width 0.2s;
  white-space: nowrap;
  overflow: hidden;
}
.sidebar.collapsed .sidebar-label {
  opacity: 0;
  width: 0;
  pointer-events: none;
}

.card {
  background: #1a1f2e;
  border: 1px solid #2d3548;
  border-radius: 12px;
}

.badge {
  font-family: 'DM Mono', monospace;
  font-size: 11px;
  letter-spacing: 0.05em;
  padding: 2px 8px;
  border-radius: 4px;
}

::-webkit-scrollbar { width: 6px; }
::-webkit-scrollbar-track { background: transparent; }
::-webkit-scrollbar-thumb { background: #2d3548; border-radius: 3px; }
CSS

success "CSS生成完了"

# ---------- 3. main.tsx ----------
section "3. main.tsx"
cat > "$FRONTEND/main.tsx" << 'TSX'
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { BrowserRouter } from 'react-router-dom'
import App from './App'
import './index.css'

const queryClient = new QueryClient({
  defaultOptions: { queries: { retry: 1, staleTime: 30_000 } },
})

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <App />
      </BrowserRouter>
    </QueryClientProvider>
  </StrictMode>,
)
TSX

# ---------- 4. App.tsx ----------
section "4. App.tsx"
cat > "$FRONTEND/App.tsx" << 'TSX'
import { Routes, Route, Navigate } from 'react-router-dom'
import { useState, useEffect } from 'react'
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

# ---------- 5. Layout ----------
section "5. Layout コンポーネント"
mkdir -p "$FRONTEND/components"
cat > "$FRONTEND/components/Layout.tsx" << 'TSX'
import { useState } from 'react'
import { Outlet, NavLink, useNavigate } from 'react-router-dom'
import {
  LayoutDashboard,
  ListChecks,
  PlusCircle,
  Users,
  LogOut,
  ChevronLeft,
  ChevronRight,
  Zap,
  Bell,
} from 'lucide-react'

const NAV = [
  { to: '/', icon: LayoutDashboard, label: 'ダッシュボード', end: true },
  { to: '/issues', icon: ListChecks, label: '課題一覧' },
  { to: '/inputs/new', icon: PlusCircle, label: '要望登録' },
  { to: '/users', icon: Users, label: 'ユーザー管理' },
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
      {/* ── Sidebar ── */}
      <aside
        className={`sidebar${collapsed ? ' collapsed' : ''}`}
        style={{
          position: 'fixed',
          top: 0,
          left: 0,
          height: '100vh',
          background: '#13171f',
          borderRight: '1px solid #1e2535',
          display: 'flex',
          flexDirection: 'column',
          zIndex: 50,
          overflow: 'hidden',
        }}
      >
        {/* Logo */}
        <div style={{ padding: '20px 16px 16px', display: 'flex', alignItems: 'center', gap: 10 }}>
          <div style={{
            width: 32, height: 32, borderRadius: 8,
            background: 'linear-gradient(135deg, #6366f1, #8b5cf6)',
            display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
          }}>
            <Zap size={16} color="#fff" />
          </div>
          <span
            className="sidebar-label"
            style={{ fontWeight: 700, fontSize: 15, color: '#f1f5f9', letterSpacing: '-0.02em' }}
          >
            decision-os
          </span>
        </div>

        {/* Nav */}
        <nav style={{ flex: 1, padding: '8px 8px' }}>
          {NAV.map(({ to, icon: Icon, label, end }) => (
            <NavLink
              key={to}
              to={to}
              end={end}
              style={({ isActive }) => ({
                display: 'flex',
                alignItems: 'center',
                gap: 10,
                padding: '9px 12px',
                borderRadius: 8,
                marginBottom: 2,
                color: isActive ? '#818cf8' : '#94a3b8',
                background: isActive ? 'rgba(99,102,241,0.12)' : 'transparent',
                textDecoration: 'none',
                fontSize: 14,
                fontWeight: isActive ? 600 : 400,
                transition: 'all 0.15s',
              })}
              onMouseEnter={e => {
                const el = e.currentTarget as HTMLAnchorElement
                if (!el.classList.contains('active')) {
                  el.style.background = 'rgba(255,255,255,0.04)'
                  el.style.color = '#e2e8f0'
                }
              }}
              onMouseLeave={e => {
                const el = e.currentTarget as HTMLAnchorElement
                if (!el.classList.contains('active')) {
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
              border: 'none', color: '#64748b', cursor: 'pointer', fontSize: 14,
              transition: 'all 0.15s',
            }}
            onMouseEnter={e => {
              const el = e.currentTarget as HTMLButtonElement
              el.style.background = 'rgba(239,68,68,0.1)'
              el.style.color = '#ef4444'
            }}
            onMouseLeave={e => {
              const el = e.currentTarget as HTMLButtonElement
              el.style.background = 'transparent'
              el.style.color = '#64748b'
            }}
          >
            <LogOut size={18} style={{ flexShrink: 0 }} />
            <span className="sidebar-label">ログアウト</span>
          </button>
        </div>

        {/* Toggle button */}
        <button
          onClick={() => setCollapsed(!collapsed)}
          style={{
            position: 'absolute', top: '50%', right: -12,
            transform: 'translateY(-50%)',
            width: 24, height: 24, borderRadius: '50%',
            background: '#1e2535', border: '1px solid #2d3548',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            cursor: 'pointer', color: '#64748b', zIndex: 10,
          }}
        >
          {collapsed ? <ChevronRight size={12} /> : <ChevronLeft size={12} />}
        </button>
      </aside>

      {/* ── Main content ── */}
      <div
        style={{
          flex: 1,
          marginLeft: collapsed ? 'var(--sidebar-collapsed-w)' : 'var(--sidebar-w)',
          transition: 'margin-left 0.25s cubic-bezier(0.4, 0, 0.2, 1)',
          display: 'flex',
          flexDirection: 'column',
          minHeight: '100vh',
        }}
      >
        {/* Top bar */}
        <header style={{
          height: 56,
          background: '#13171f',
          borderBottom: '1px solid #1e2535',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'flex-end',
          padding: '0 24px',
          gap: 12,
          position: 'sticky', top: 0, zIndex: 40,
        }}>
          <button style={{
            width: 36, height: 36, borderRadius: 8,
            background: 'transparent', border: '1px solid #2d3548',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            cursor: 'pointer', color: '#64748b',
          }}>
            <Bell size={16} />
          </button>
          <div style={{
            width: 32, height: 32, borderRadius: '50%',
            background: 'linear-gradient(135deg, #6366f1, #8b5cf6)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontSize: 13, fontWeight: 600, color: '#fff',
          }}>
            U
          </div>
        </header>

        <main style={{ flex: 1, padding: '28px 32px' }}>
          <Outlet />
        </main>
      </div>
    </div>
  )
}
TSX

# ---------- 6. IssueList.tsx (バグ修正 + デザイン) ----------
section "6. IssueList.tsx（バグ修正 + リデザイン）"
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

type StatusKey = 'open' | 'in_progress' | 'closed' | string

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
  if (Array.isArray(data)) return { items: data, total: data.length }
  if (Array.isArray(data?.items)) return { items: data.items, total: data.total ?? data.items.length }
  if (Array.isArray(data?.issues)) return { items: data.issues, total: data.total ?? data.issues.length }
  // オブジェクトなら値を探す
  const arr = Object.values(data).find((v): v is Issue[] => Array.isArray(v))
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
    placeholderData: prev => prev,
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
          >
            ←
          </button>
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
          >
            →
          </button>
        </div>
      )}
    </div>
  )
}
TSX

# ---------- 7. Dashboard リデザイン ----------
section "7. Dashboard リデザイン"
cat > "$FRONTEND/pages/Dashboard.tsx" << 'TSX'
import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { ArrowRight, Inbox, Zap, AlertCircle, TrendingUp } from 'lucide-react'
import apiClient from '@/api/client'

interface DashboardStats {
  unprocessed_inputs?: number
  pending_action_items?: number
  open_issues?: number
  total_inputs?: number
  total_items?: number
  total_issues?: number
}

interface RecentIssue {
  id: string
  title: string
  status: string
  created_at: string
}

const STATUS_STYLE: Record<string, { bg: string; color: string; label: string }> = {
  open:        { bg: 'rgba(59,130,246,0.15)',  color: '#60a5fa', label: 'open' },
  in_progress: { bg: 'rgba(245,158,11,0.15)',  color: '#fbbf24', label: 'in_progress' },
  doing:       { bg: 'rgba(245,158,11,0.15)',  color: '#fbbf24', label: 'doing' },
  done:        { bg: 'rgba(34,197,94,0.15)',   color: '#4ade80', label: 'done' },
  closed:      { bg: 'rgba(100,116,139,0.15)', color: '#94a3b8', label: 'closed' },
}

async function fetchStats(): Promise<DashboardStats> {
  const res = await apiClient.get('/dashboard/stats').catch(() => ({ data: {} }))
  return res.data ?? {}
}

async function fetchRecentIssues(): Promise<RecentIssue[]> {
  const res = await apiClient.get('/issues?limit=5&skip=0')
  const d = res.data
  if (Array.isArray(d)) return d
  if (Array.isArray(d?.items)) return d.items
  const arr = Object.values(d).find((v): v is RecentIssue[] => Array.isArray(v))
  return arr ?? []
}

export default function Dashboard() {
  const { data: stats } = useQuery({ queryKey: ['stats'], queryFn: fetchStats })
  const { data: recent = [] } = useQuery({ queryKey: ['recent-issues'], queryFn: fetchRecentIssues })

  const CARDS = [
    {
      label: '未処理 INPUT',
      value: stats?.unprocessed_inputs ?? 0,
      sub: `総数 ${stats?.total_inputs ?? 0}件`,
      icon: Inbox,
      color: '#60a5fa',
      gradient: 'rgba(59,130,246,0.12)',
    },
    {
      label: 'ACTION待ち ITEM',
      value: stats?.pending_action_items ?? 0,
      sub: '要判断',
      icon: Zap,
      color: '#a78bfa',
      gradient: 'rgba(139,92,246,0.12)',
    },
    {
      label: '未完了 ISSUE',
      value: stats?.open_issues ?? 0,
      sub: `総数 ${stats?.total_issues ?? 0}件`,
      icon: AlertCircle,
      color: '#f472b6',
      gradient: 'rgba(244,114,182,0.12)',
    },
  ]

  return (
    <div>
      <div style={{ marginBottom: 28 }}>
        <h1 style={{ margin: 0, fontSize: 22, fontWeight: 700, color: '#f1f5f9', letterSpacing: '-0.03em' }}>
          ダッシュボード
        </h1>
        <p style={{ margin: '4px 0 0', fontSize: 13, color: '#64748b' }}>
          {new Date().toLocaleDateString('ja-JP', { year: 'numeric', month: 'long', day: 'numeric', weekday: 'short' })}
        </p>
      </div>

      {/* Stats */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 16, marginBottom: 24 }}>
        {CARDS.map(({ label, value, sub, icon: Icon, color, gradient }) => (
          <div key={label} className="card" style={{ padding: '20px 24px', position: 'relative', overflow: 'hidden' }}>
            <div style={{
              position: 'absolute', top: 0, right: 0, width: 80, height: 80,
              background: gradient, borderRadius: '0 12px 0 80px',
            }} />
            <div style={{
              width: 36, height: 36, borderRadius: 8, background: gradient,
              display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 14,
            }}>
              <Icon size={18} color={color} />
            </div>
            <div style={{ fontSize: 32, fontWeight: 800, color, letterSpacing: '-0.04em', lineHeight: 1 }}>
              {value.toLocaleString()}
            </div>
            <div style={{ marginTop: 6, fontSize: 12, color: '#94a3b8', fontWeight: 600 }}>{label}</div>
            <div style={{ marginTop: 2, fontSize: 11, color: '#475569', fontFamily: 'DM Mono, monospace' }}>{sub}</div>
          </div>
        ))}
      </div>

      {/* Recent Issues */}
      <div className="card" style={{ overflow: 'hidden' }}>
        <div style={{
          padding: '16px 20px', borderBottom: '1px solid #1e2535',
          display: 'flex', justifyContent: 'space-between', alignItems: 'center',
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <TrendingUp size={16} color="#818cf8" />
            <span style={{ fontWeight: 600, fontSize: 14, color: '#e2e8f0' }}>直近の課題</span>
          </div>
          <Link
            to="/issues"
            style={{ display: 'flex', alignItems: 'center', gap: 4, color: '#818cf8', textDecoration: 'none', fontSize: 12 }}
          >
            すべて見る <ArrowRight size={13} />
          </Link>
        </div>
        {recent.length === 0 ? (
          <div style={{ padding: '40px', textAlign: 'center', color: '#475569', fontSize: 13 }}>
            課題はまだありません
          </div>
        ) : (
          recent.map((issue, i) => {
            const st = STATUS_STYLE[issue.status] ?? STATUS_STYLE['open']
            return (
              <Link
                key={issue.id}
                to={`/issues/${issue.id}`}
                style={{
                  display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                  padding: '13px 20px', textDecoration: 'none',
                  borderBottom: i < recent.length - 1 ? '1px solid #1a2030' : 'none',
                  transition: 'background 0.1s',
                }}
                onMouseEnter={e => (e.currentTarget.style.background = 'rgba(255,255,255,0.025)')}
                onMouseLeave={e => (e.currentTarget.style.background = 'transparent')}
              >
                <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                  <div style={{ width: 6, height: 6, borderRadius: '50%', background: st.color, flexShrink: 0 }} />
                  <span style={{ color: '#e2e8f0', fontSize: 13, fontWeight: 500 }}>{issue.title}</span>
                </div>
                <span className="badge" style={{ background: st.bg, color: st.color }}>{st.label}</span>
              </Link>
            )
          })
        )}
      </div>
    </div>
  )
}
TSX

# ---------- 8. Login ページ ----------
section "8. Login ページ"
cat > "$FRONTEND/pages/Login.tsx" << 'TSX'
import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Zap, Loader2 } from 'lucide-react'
import apiClient from '@/api/client'

export default function Login() {
  const [email, setEmail]     = useState('demo@example.com')
  const [password, setPassword] = useState('demo1234')
  const [error, setError]     = useState('')
  const [loading, setLoading] = useState(false)
  const navigate = useNavigate()

  async function handleLogin() {
    setLoading(true); setError('')
    try {
      const form = new URLSearchParams()
      form.set('username', email); form.set('password', password)
      const res = await apiClient.post('/auth/login', form, {
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      })
      localStorage.setItem('access_token', res.data.access_token)
      navigate('/')
    } catch (e: unknown) {
      setError('ログインに失敗しました。メールアドレスとパスワードを確認してください。')
    } finally {
      setLoading(false)
    }
  }

  const inputStyle = {
    width: '100%', padding: '10px 14px',
    background: '#1a1f2e', border: '1px solid #2d3548',
    borderRadius: 8, color: '#e2e8f0', fontSize: 14,
    outline: 'none', marginBottom: 12,
  }

  return (
    <div style={{
      minHeight: '100vh', background: '#0f1117',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
    }}>
      {/* Background glow */}
      <div style={{
        position: 'fixed', top: '20%', left: '50%', transform: 'translateX(-50%)',
        width: 600, height: 300,
        background: 'radial-gradient(ellipse, rgba(99,102,241,0.15) 0%, transparent 70%)',
        pointerEvents: 'none',
      }} />

      <div className="card" style={{ width: '100%', maxWidth: 380, padding: '36px 32px', position: 'relative' }}>
        <div style={{ textAlign: 'center', marginBottom: 28 }}>
          <div style={{
            width: 44, height: 44, borderRadius: 12,
            background: 'linear-gradient(135deg, #6366f1, #8b5cf6)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            margin: '0 auto 14px',
          }}>
            <Zap size={22} color="#fff" />
          </div>
          <h1 style={{ margin: 0, fontSize: 20, fontWeight: 700, color: '#f1f5f9', letterSpacing: '-0.03em' }}>
            decision-os
          </h1>
          <p style={{ margin: '6px 0 0', fontSize: 13, color: '#64748b' }}>開発判断OS — ログイン</p>
        </div>

        <input
          type="email" value={email} onChange={e => setEmail(e.target.value)}
          placeholder="メールアドレス" style={inputStyle}
        />
        <input
          type="password" value={password} onChange={e => setPassword(e.target.value)}
          placeholder="パスワード" style={inputStyle}
          onKeyDown={e => e.key === 'Enter' && handleLogin()}
        />

        {error && (
          <div style={{ background: 'rgba(239,68,68,0.1)', border: '1px solid rgba(239,68,68,0.3)', borderRadius: 6, padding: '8px 12px', marginBottom: 12, color: '#f87171', fontSize: 12 }}>
            {error}
          </div>
        )}

        <button
          onClick={handleLogin}
          disabled={loading}
          style={{
            width: '100%', padding: '11px', borderRadius: 8, border: 'none',
            background: 'linear-gradient(135deg, #6366f1, #8b5cf6)',
            color: '#fff', fontWeight: 600, fontSize: 14, cursor: 'pointer',
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6,
            opacity: loading ? 0.7 : 1,
          }}
        >
          {loading ? <><Loader2 size={15} style={{ animation: 'spin 1s linear infinite' }} /> ログイン中...</> : 'ログイン'}
        </button>

        <style>{`@keyframes spin { to { transform: rotate(360deg) } }`}</style>
      </div>
    </div>
  )
}
TSX

# ---------- 9. 既存ページのスタブ（存在しない場合のみ生成）----------
section "9. スタブページ確認"

# InputNew
if [ ! -f "$FRONTEND/pages/InputNew.tsx" ]; then
cat > "$FRONTEND/pages/InputNew.tsx" << 'TSX'
export default function InputNew() {
  return (
    <div>
      <h1 style={{ margin: '0 0 8px', fontSize: 22, fontWeight: 700, color: '#f1f5f9', letterSpacing: '-0.03em' }}>要望登録</h1>
      <p style={{ color: '#64748b', fontSize: 13 }}>テキストを入力して分解エンジンへ送信します。</p>
      <div className="card" style={{ padding: 24, marginTop: 20, color: '#94a3b8', fontSize: 14 }}>
        実装予定のページです。
      </div>
    </div>
  )
}
TSX
fi

# IssueDetail
if [ ! -f "$FRONTEND/pages/IssueDetail.tsx" ]; then
cat > "$FRONTEND/pages/IssueDetail.tsx" << 'TSX'
import { useParams, Link } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { ArrowLeft } from 'lucide-react'
import apiClient from '@/api/client'

export default function IssueDetail() {
  const { id } = useParams<{ id: string }>()
  const { data: issue, isLoading } = useQuery({
    queryKey: ['issue', id],
    queryFn: async () => (await apiClient.get(`/issues/${id}`)).data,
  })

  if (isLoading) return <div style={{ color: '#64748b', padding: 40 }}>読み込み中...</div>
  if (!issue) return <div style={{ color: '#ef4444', padding: 40 }}>課題が見つかりません</div>

  return (
    <div>
      <Link to="/issues" style={{ display: 'inline-flex', alignItems: 'center', gap: 6, color: '#64748b', textDecoration: 'none', fontSize: 13, marginBottom: 20 }}>
        <ArrowLeft size={14} /> 課題一覧に戻る
      </Link>
      <h1 style={{ margin: '0 0 16px', fontSize: 20, fontWeight: 700, color: '#f1f5f9' }}>{issue.title}</h1>
      <div className="card" style={{ padding: 24 }}>
        <pre style={{ color: '#94a3b8', fontSize: 13, margin: 0, whiteSpace: 'pre-wrap' }}>
          {JSON.stringify(issue, null, 2)}
        </pre>
      </div>
    </div>
  )
}
TSX
fi

# UserManagement
if [ ! -f "$FRONTEND/pages/UserManagement.tsx" ]; then
cat > "$FRONTEND/pages/UserManagement.tsx" << 'TSX'
export default function UserManagement() {
  return (
    <div>
      <h1 style={{ margin: '0 0 8px', fontSize: 22, fontWeight: 700, color: '#f1f5f9', letterSpacing: '-0.03em' }}>ユーザー管理</h1>
      <div className="card" style={{ padding: 24, marginTop: 20, color: '#94a3b8', fontSize: 14 }}>Admin専用ページです。</div>
    </div>
  )
}
TSX
fi

success "スタブページ確認完了"

# ---------- 10. ビルド確認 ----------
section "10. ビルド確認"
cd "$PROJECT_DIR/frontend"
npm run typecheck 2>&1 | tail -5 && success "型チェック OK" || warn "型チェック警告あり（続行）"

# ---------- 完了 ----------
section "完了"
echo -e "${GREEN}"
echo "  ✔ IssueList バグ修正（APIレスポンス形式の正規化）"
echo "  ✔ UIリデザイン（スタイリッシュなダークテーマ）"
echo "  ✔ サイドバー：折り畳み可能（アイコン ↔ アイコン＋テキスト）"
echo "  ✔ Dashboard、Login、IssueList リデザイン完了"
echo -e "${RESET}"
echo -e "${YELLOW}【フロントエンド再起動】${RESET}"
echo -e "  cd ~/projects/decision-os/frontend && npm run dev -- --host 0.0.0.0 --port 3008"
echo -e "  → http://localhost:3008 を開いてください"
