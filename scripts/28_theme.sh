#!/usr/bin/env bash
# =============================================================================
# decision-os / 28: ライト/ダークテーマ切り替え実装（デフォルト: ライト）
# =============================================================================
set -euo pipefail
GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

FRONTEND="$HOME/projects/decision-os/frontend/src"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
nvm use 20 2>/dev/null || true

# =============================================================================
section "1. ThemeContext — テーマ管理"
# =============================================================================
mkdir -p "$FRONTEND/contexts"
cat > "$FRONTEND/contexts/ThemeContext.tsx" << 'TSX'
import { createContext, useContext, useState, useEffect } from 'react'

type Theme = 'light' | 'dark'
const ThemeContext = createContext<{ theme: Theme; toggle: () => void }>({
  theme: 'light',
  toggle: () => {},
})

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [theme, setTheme] = useState<Theme>(() => {
    return (localStorage.getItem('dos-theme') as Theme) ?? 'light'
  })

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme)
    localStorage.setItem('dos-theme', theme)
  }, [theme])

  const toggle = () => setTheme(t => t === 'light' ? 'dark' : 'light')

  return (
    <ThemeContext.Provider value={{ theme, toggle }}>
      {children}
    </ThemeContext.Provider>
  )
}

export const useTheme = () => useContext(ThemeContext)
TSX
success "ThemeContext 生成完了"

# =============================================================================
section "2. index.css — CSS変数ベースのテーマシステム"
# =============================================================================
cat > "$FRONTEND/index.css" << 'CSS'
@import url('https://fonts.googleapis.com/css2?family=DM+Sans:ital,opsz,wght@0,9..40,300;0,9..40,400;0,9..40,500;0,9..40,600;1,9..40,400&family=DM+Mono:wght@400;500&display=swap');

/* ── ライトテーマ（デフォルト）─────────────────────────── */
:root, [data-theme="light"] {
  --bg-base:       #f5f6fa;
  --bg-surface:    #ffffff;
  --bg-sidebar:    #1e2035;
  --bg-input:      #f0f1f5;
  --bg-hover:      #f0f1f8;
  --bg-tag:        #eef0ff;

  --border:        #e2e5ee;
  --border-strong: #c8ccdb;

  --text-primary:  #1a1d2e;
  --text-secondary:#4b5068;
  --text-muted:    #8b90a7;
  --text-sidebar:  #a8b0cc;
  --text-sidebar-active: #ffffff;

  --accent:        #4f46e5;
  --accent-light:  rgba(79,70,229,0.1);
  --accent-glow:   rgba(79,70,229,0.25);

  --sidebar-active-bg: rgba(255,255,255,0.12);
  --sidebar-hover-bg:  rgba(255,255,255,0.06);

  --shadow-card:   0 1px 3px rgba(0,0,0,0.08), 0 1px 2px rgba(0,0,0,0.04);
  --shadow-lg:     0 4px 16px rgba(0,0,0,0.1);

  --status-open-bg:  rgba(59,130,246,0.1);  --status-open-fg:  #2563eb;
  --status-prog-bg:  rgba(245,158,11,0.1);  --status-prog-fg:  #d97706;
  --status-done-bg:  rgba(22,163,74,0.1);   --status-done-fg:  #16a34a;
  --status-closed-bg:rgba(100,116,139,0.1); --status-closed-fg:#64748b;
}

/* ── ダークテーマ ───────────────────────────────────────── */
[data-theme="dark"] {
  --bg-base:       #0f1117;
  --bg-surface:    #1a1f2e;
  --bg-sidebar:    #13171f;
  --bg-input:      #0f1117;
  --bg-hover:      rgba(255,255,255,0.03);
  --bg-tag:        rgba(99,102,241,0.15);

  --border:        #2d3548;
  --border-strong: #3d4560;

  --text-primary:  #e2e8f0;
  --text-secondary:#94a3b8;
  --text-muted:    #64748b;
  --text-sidebar:  #94a3b8;
  --text-sidebar-active: #818cf8;

  --accent:        #6366f1;
  --accent-light:  rgba(99,102,241,0.12);
  --accent-glow:   rgba(99,102,241,0.3);

  --sidebar-active-bg: rgba(99,102,241,0.12);
  --sidebar-hover-bg:  rgba(255,255,255,0.04);

  --shadow-card:   none;
  --shadow-lg:     0 4px 12px rgba(0,0,0,0.4);

  --status-open-bg:  rgba(59,130,246,0.15);  --status-open-fg:  #60a5fa;
  --status-prog-bg:  rgba(245,158,11,0.15);  --status-prog-fg:  #fbbf24;
  --status-done-bg:  rgba(34,197,94,0.15);   --status-done-fg:  #4ade80;
  --status-closed-bg:rgba(100,116,139,0.15); --status-closed-fg:#94a3b8;
}

/* ── ベーススタイル ─────────────────────────────────────── */
*, *::before, *::after { box-sizing: border-box; }

html { transition: background 0.2s, color 0.2s; }

body {
  font-family: 'DM Sans', sans-serif;
  background: var(--bg-base);
  color: var(--text-primary);
  margin: 0;
  -webkit-font-smoothing: antialiased;
}

:root {
  --sidebar-w: 232px;
  --sidebar-collapsed-w: 60px;
}

/* ── サイドバートランジション ───────────────────────────── */
.sidebar {
  width: var(--sidebar-w);
  transition: width 0.25s cubic-bezier(0.4,0,0.2,1);
}
.sidebar.collapsed { width: var(--sidebar-collapsed-w); }
.sidebar-label {
  transition: opacity 0.2s, width 0.2s;
  white-space: nowrap; overflow: hidden;
}
.sidebar.collapsed .sidebar-label {
  opacity: 0; width: 0; pointer-events: none;
}

/* ── カード ─────────────────────────────────────────────── */
.card {
  background: var(--bg-surface);
  border: 1px solid var(--border);
  border-radius: 12px;
  box-shadow: var(--shadow-card);
}

/* ── バッジ ─────────────────────────────────────────────── */
.badge {
  font-family: 'DM Mono', monospace;
  font-size: 11px;
  letter-spacing: 0.04em;
  padding: 2px 8px;
  border-radius: 4px;
  font-weight: 500;
}

/* ── フォームコントロール ───────────────────────────────── */
input, select, textarea {
  background: var(--bg-input);
  border: 1px solid var(--border);
  color: var(--text-primary);
  border-radius: 8px;
  font-family: inherit;
  font-size: 14px;
  transition: border-color 0.15s;
}
input::placeholder, textarea::placeholder { color: var(--text-muted); }
input:focus, select:focus, textarea:focus {
  outline: none;
  border-color: var(--accent);
  box-shadow: 0 0 0 3px var(--accent-light);
}

/* ── スクロールバー ─────────────────────────────────────── */
::-webkit-scrollbar { width: 5px; }
::-webkit-scrollbar-track { background: transparent; }
::-webkit-scrollbar-thumb { background: var(--border); border-radius: 3px; }

/* ── テーブル ───────────────────────────────────────────── */
table { border-collapse: collapse; }
CSS
success "index.css 生成完了"

# =============================================================================
section "3. main.tsx — ThemeProvider でラップ"
# =============================================================================
cat > "$FRONTEND/main.tsx" << 'TSX'
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { BrowserRouter } from 'react-router-dom'
import { ThemeProvider } from '@/contexts/ThemeContext'
import App from './App'
import './index.css'

const queryClient = new QueryClient({
  defaultOptions: { queries: { retry: 1, staleTime: 30_000 } },
})

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ThemeProvider>
      <QueryClientProvider client={queryClient}>
        <BrowserRouter>
          <App />
        </BrowserRouter>
      </QueryClientProvider>
    </ThemeProvider>
  </StrictMode>,
)
TSX
success "main.tsx 更新完了"

# =============================================================================
section "4. ThemeToggle コンポーネント"
# =============================================================================
cat > "$FRONTEND/components/ThemeToggle.tsx" << 'TSX'
import { Sun, Moon } from 'lucide-react'
import { useTheme } from '@/contexts/ThemeContext'

export default function ThemeToggle({ size = 'md' }: { size?: 'sm' | 'md' }) {
  const { theme, toggle } = useTheme()
  const isLight = theme === 'light'
  const px = size === 'sm' ? '6px 10px' : '7px 12px'

  return (
    <button
      onClick={toggle}
      title={isLight ? 'ダークモードに切り替え' : 'ライトモードに切り替え'}
      style={{
        display: 'inline-flex', alignItems: 'center', gap: 6,
        padding: px, borderRadius: 8,
        background: 'var(--bg-input)', border: '1px solid var(--border)',
        color: 'var(--text-secondary)', cursor: 'pointer',
        fontSize: 12, fontWeight: 500, transition: 'all 0.15s',
        fontFamily: 'DM Sans, sans-serif',
      }}
      onMouseEnter={e => {
        const el = e.currentTarget as HTMLButtonElement
        el.style.borderColor = 'var(--accent)'
        el.style.color = 'var(--accent)'
      }}
      onMouseLeave={e => {
        const el = e.currentTarget as HTMLButtonElement
        el.style.borderColor = 'var(--border)'
        el.style.color = 'var(--text-secondary)'
      }}
    >
      {isLight ? <Moon size={14} /> : <Sun size={14} />}
      {size === 'md' && <span>{isLight ? 'Dark' : 'Light'}</span>}
    </button>
  )
}
TSX
success "ThemeToggle 生成完了"

# =============================================================================
section "5. Layout.tsx — CSS変数ベース + トグルボタン"
# =============================================================================
cat > "$FRONTEND/components/Layout.tsx" << 'TSX'
import { useState } from 'react'
import { Outlet, NavLink, useNavigate } from 'react-router-dom'
import {
  LayoutDashboard, ListChecks, PlusCircle, Users,
  LogOut, ChevronLeft, ChevronRight, Zap, Bell, History,
} from 'lucide-react'
import ThemeToggle from '@/components/ThemeToggle'

const NAV = [
  { to: '/',           icon: LayoutDashboard, label: 'ダッシュボード', end: true },
  { to: '/issues',     icon: ListChecks,      label: '課題一覧' },
  { to: '/inputs',     icon: History,         label: '要望履歴' },
  { to: '/inputs/new', icon: PlusCircle,      label: '要望登録' },
  { to: '/users',      icon: Users,           label: 'ユーザー管理' },
]

export default function Layout() {
  const [collapsed, setCollapsed] = useState(false)
  const navigate = useNavigate()

  return (
    <div style={{ display: 'flex', minHeight: '100vh', background: 'var(--bg-base)' }}>

      {/* ── Sidebar ── */}
      <aside
        className={`sidebar${collapsed ? ' collapsed' : ''}`}
        style={{
          position: 'fixed', top: 0, left: 0, height: '100vh',
          background: 'var(--bg-sidebar)',
          borderRight: '1px solid rgba(255,255,255,0.06)',
          display: 'flex', flexDirection: 'column', zIndex: 50, overflow: 'hidden',
        }}
      >
        {/* Logo */}
        <div style={{ padding: '18px 14px 14px', display: 'flex', alignItems: 'center', gap: 10 }}>
          <div style={{
            width: 32, height: 32, borderRadius: 8, flexShrink: 0,
            background: 'linear-gradient(135deg, #6366f1, #8b5cf6)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <Zap size={16} color="#fff" />
          </div>
          <span className="sidebar-label" style={{ fontWeight: 700, fontSize: 15, color: '#fff', letterSpacing: '-0.02em' }}>
            decision-os
          </span>
        </div>

        {/* Divider */}
        <div style={{ height: 1, background: 'rgba(255,255,255,0.07)', margin: '0 14px 8px' }} />

        {/* Nav */}
        <nav style={{ flex: 1, padding: '4px 8px', overflowY: 'auto' }}>
          {NAV.map(({ to, icon: Icon, label, end }) => (
            <NavLink
              key={to}
              to={to}
              end={end}
              style={({ isActive }) => ({
                display: 'flex', alignItems: 'center', gap: 10,
                padding: '8px 10px', borderRadius: 8, marginBottom: 2,
                color: isActive ? '#fff' : 'rgba(180,188,210,0.85)',
                background: isActive ? 'rgba(99,102,241,0.35)' : 'transparent',
                textDecoration: 'none', fontSize: 13.5,
                fontWeight: isActive ? 600 : 400, transition: 'all 0.12s',
              })}
              onMouseEnter={e => {
                const el = e.currentTarget as HTMLAnchorElement
                if (!el.getAttribute('aria-current')) {
                  el.style.background = 'rgba(255,255,255,0.07)'
                  el.style.color = '#fff'
                }
              }}
              onMouseLeave={e => {
                const el = e.currentTarget as HTMLAnchorElement
                if (!el.getAttribute('aria-current')) {
                  el.style.background = 'transparent'
                  el.style.color = 'rgba(180,188,210,0.85)'
                }
              }}
            >
              <Icon size={17} style={{ flexShrink: 0, opacity: 0.9 }} />
              <span className="sidebar-label">{label}</span>
            </NavLink>
          ))}
        </nav>

        {/* Bottom */}
        <div style={{ padding: '8px 8px 18px', borderTop: '1px solid rgba(255,255,255,0.07)' }}>
          <button
            onClick={() => { localStorage.removeItem('access_token'); navigate('/login') }}
            style={{
              display: 'flex', alignItems: 'center', gap: 10, width: '100%',
              padding: '8px 10px', borderRadius: 8, background: 'transparent',
              border: 'none', color: 'rgba(180,188,210,0.6)', cursor: 'pointer',
              fontSize: 13.5, transition: 'all 0.12s',
            }}
            onMouseEnter={e => { const el = e.currentTarget as HTMLButtonElement; el.style.background = 'rgba(239,68,68,0.15)'; el.style.color = '#fca5a5' }}
            onMouseLeave={e => { const el = e.currentTarget as HTMLButtonElement; el.style.background = 'transparent'; el.style.color = 'rgba(180,188,210,0.6)' }}
          >
            <LogOut size={17} style={{ flexShrink: 0 }} />
            <span className="sidebar-label">ログアウト</span>
          </button>
        </div>

        {/* Collapse toggle */}
        <button
          onClick={() => setCollapsed(!collapsed)}
          style={{
            position: 'absolute', top: '50%', right: -11,
            transform: 'translateY(-50%)', width: 22, height: 22, borderRadius: '50%',
            background: '#2d3250', border: '1px solid rgba(255,255,255,0.12)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            cursor: 'pointer', color: 'rgba(180,188,210,0.7)', zIndex: 10,
          }}
        >
          {collapsed ? <ChevronRight size={11} /> : <ChevronLeft size={11} />}
        </button>
      </aside>

      {/* ── Main ── */}
      <div style={{
        flex: 1,
        marginLeft: collapsed ? 'var(--sidebar-collapsed-w)' : 'var(--sidebar-w)',
        transition: 'margin-left 0.25s cubic-bezier(0.4,0,0.2,1)',
        display: 'flex', flexDirection: 'column', minHeight: '100vh',
      }}>
        {/* Top bar */}
        <header style={{
          height: 54, background: 'var(--bg-surface)',
          borderBottom: '1px solid var(--border)',
          display: 'flex', alignItems: 'center', justifyContent: 'flex-end',
          padding: '0 24px', gap: 10, position: 'sticky', top: 0, zIndex: 40,
          boxShadow: 'var(--shadow-card)',
        }}>
          <ThemeToggle />
          <button style={{
            width: 34, height: 34, borderRadius: 8,
            background: 'var(--bg-input)', border: '1px solid var(--border)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            cursor: 'pointer', color: 'var(--text-muted)',
          }}>
            <Bell size={15} />
          </button>
          <div style={{
            width: 32, height: 32, borderRadius: '50%',
            background: 'linear-gradient(135deg, #6366f1, #8b5cf6)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontSize: 12, fontWeight: 700, color: '#fff',
          }}>U</div>
        </header>

        <main style={{ flex: 1, padding: '28px 32px', maxWidth: 1200 }}>
          <Outlet />
        </main>
      </div>
    </div>
  )
}
TSX
success "Layout.tsx 更新完了"

# =============================================================================
section "6. Login.tsx — ライト/ダーク対応"
# =============================================================================
cat > "$FRONTEND/pages/Login.tsx" << 'TSX'
import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Zap, Loader2 } from 'lucide-react'
import apiClient from '@/api/client'
import ThemeToggle from '@/components/ThemeToggle'

export default function Login() {
  const [email, setEmail]       = useState('demo@example.com')
  const [password, setPassword] = useState('demo1234')
  const [error, setError]       = useState('')
  const [loading, setLoading]   = useState(false)
  const navigate = useNavigate()

  async function handleLogin() {
    setLoading(true); setError('')
    try {
      const res = await apiClient.post('/auth/login', { email, password })
      const token = res.data.access_token
      if (!token) throw new Error('no token')
      localStorage.setItem('access_token', token)
      navigate('/')
    } catch (e: unknown) {
      const detail = (e as { response?: { data?: { detail?: string } } })?.response?.data?.detail
      setError(typeof detail === 'string' ? detail : 'ログインに失敗しました')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div style={{
      minHeight: '100vh',
      background: 'var(--bg-base)',
      display: 'flex', flexDirection: 'column',
      alignItems: 'center', justifyContent: 'center',
      position: 'relative',
    }}>
      {/* Theme toggle — top right */}
      <div style={{ position: 'fixed', top: 16, right: 20 }}>
        <ThemeToggle />
      </div>

      {/* Decorative top accent */}
      <div style={{
        position: 'fixed', top: 0, left: 0, right: 0, height: 3,
        background: 'linear-gradient(90deg, #6366f1, #8b5cf6, #ec4899)',
      }} />

      {/* Card */}
      <div className="card" style={{
        width: '100%', maxWidth: 400,
        padding: '40px 36px',
        boxShadow: 'var(--shadow-lg)',
      }}>
        {/* Logo */}
        <div style={{ textAlign: 'center', marginBottom: 32 }}>
          <div style={{
            width: 48, height: 48, borderRadius: 14,
            background: 'linear-gradient(135deg, #6366f1, #8b5cf6)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            margin: '0 auto 16px',
            boxShadow: '0 8px 24px rgba(99,102,241,0.3)',
          }}>
            <Zap size={24} color="#fff" />
          </div>
          <h1 style={{ margin: 0, fontSize: 22, fontWeight: 800, color: 'var(--text-primary)', letterSpacing: '-0.04em' }}>
            decision-os
          </h1>
          <p style={{ margin: '6px 0 0', fontSize: 13, color: 'var(--text-muted)' }}>
            開発判断OS — サインイン
          </p>
        </div>

        {/* Fields */}
        <div style={{ marginBottom: 12 }}>
          <label style={{ display: 'block', fontSize: 12, fontWeight: 600, color: 'var(--text-secondary)', marginBottom: 6 }}>
            メールアドレス
          </label>
          <input
            type="email" value={email}
            onChange={e => setEmail(e.target.value)}
            placeholder="you@example.com"
            style={{ width: '100%', padding: '10px 14px' }}
          />
        </div>

        <div style={{ marginBottom: 20 }}>
          <label style={{ display: 'block', fontSize: 12, fontWeight: 600, color: 'var(--text-secondary)', marginBottom: 6 }}>
            パスワード
          </label>
          <input
            type="password" value={password}
            onChange={e => setPassword(e.target.value)}
            placeholder="••••••••"
            style={{ width: '100%', padding: '10px 14px' }}
            onKeyDown={e => e.key === 'Enter' && handleLogin()}
          />
        </div>

        {error && (
          <div style={{
            background: 'rgba(239,68,68,0.08)', border: '1px solid rgba(239,68,68,0.25)',
            borderRadius: 8, padding: '10px 14px', marginBottom: 16,
            color: '#dc2626', fontSize: 13,
          }}>
            {error}
          </div>
        )}

        <button
          onClick={handleLogin}
          disabled={loading}
          style={{
            width: '100%', padding: '12px',
            background: 'linear-gradient(135deg, #6366f1, #8b5cf6)',
            border: 'none', borderRadius: 10,
            color: '#fff', fontWeight: 700, fontSize: 14,
            cursor: loading ? 'not-allowed' : 'pointer',
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
            opacity: loading ? 0.75 : 1,
            boxShadow: '0 4px 14px rgba(99,102,241,0.35)',
            fontFamily: 'DM Sans, sans-serif',
            letterSpacing: '-0.01em',
            transition: 'opacity 0.15s, transform 0.1s',
          }}
          onMouseEnter={e => { if (!loading) (e.currentTarget as HTMLButtonElement).style.transform = 'translateY(-1px)' }}
          onMouseLeave={e => { (e.currentTarget as HTMLButtonElement).style.transform = 'translateY(0)' }}
        >
          {loading
            ? <><Loader2 size={15} style={{ animation: 'spin 1s linear infinite' }} /> サインイン中...</>
            : 'サインイン'}
        </button>

        <style>{`@keyframes spin { to { transform: rotate(360deg) } }`}</style>
      </div>

      {/* Footer */}
      <p style={{ marginTop: 24, fontSize: 12, color: 'var(--text-muted)' }}>
        decision-os © 2026
      </p>
    </div>
  )
}
TSX
success "Login.tsx 更新完了"

# =============================================================================
section "7. Dashboard — CSS変数対応"
# =============================================================================
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
TSX
success "Dashboard.tsx 更新完了"

# =============================================================================
section "8. IssueList — CSS変数対応"
# =============================================================================
cat > "$FRONTEND/pages/IssueList.tsx" << 'TSX'
import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { Plus, Search, Filter, ChevronDown, AlertCircle, Loader2 } from 'lucide-react'
import apiClient from '@/api/client'

interface Issue {
  id: string; title: string; status: string
  priority?: number; issue_type?: string; created_at: string
  labels?: { name: string; color?: string }[]
}

async function fetchIssues(params: Record<string, string>) {
  const res = await apiClient.get(`/issues?${new URLSearchParams(params)}`)
  const d = res.data
  if (Array.isArray(d)) return { items: d as Issue[], total: d.length }
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
  const [search, setSearch] = useState('')
  const [status, setStatus] = useState('')
  const [page, setPage] = useState(1)
  const limit = 20
  const params: Record<string, string> = {
    skip: String((page - 1) * limit), limit: String(limit),
    ...(search ? { q: search } : {}), ...(status ? { status } : {}),
  }
  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['issues', params], queryFn: () => fetchIssues(params), placeholderData: p => p,
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
          <h1 style={{ margin: 0, fontSize: 22, fontWeight: 800, color: 'var(--text-primary)', letterSpacing: '-0.03em' }}>
            課題一覧
          </h1>
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
                      {issue.labels && issue.labels.length > 0 && (
                        <div style={{ display: 'flex', gap: 4, marginTop: 4 }}>
                          {issue.labels.map(lb => (
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
TSX
success "IssueList.tsx 更新完了"

# =============================================================================
section "9. 型チェック + 再起動"
# =============================================================================
cd "$HOME/projects/decision-os/frontend"
npm run typecheck && echo -e "${GREEN}[OK]    型チェック PASS${RESET}" || echo "[WARN]  型警告あり（続行）"

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
echo "  デフォルト: ライトモード"
echo "  右上の「Dark / Light」ボタンで切り替え可能"
echo "  設定はブラウザに記憶されます"
