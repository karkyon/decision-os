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
