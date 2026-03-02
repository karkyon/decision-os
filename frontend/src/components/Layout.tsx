import GlobalSearch from './GlobalSearch';
import { useState, useEffect, useRef } from 'react'
import { Outlet, NavLink, useNavigate } from 'react-router-dom'
import {
  LayoutDashboard, ListChecks, PlusCircle, Users,
  LogOut, ChevronLeft, ChevronRight, Zap, Bell, History,
  ChevronDown, FolderOpen, Check, Search, X,
} from 'lucide-react'
import ThemeToggle from '@/components/ThemeToggle'
import apiClient from '@/api/client'

interface Project { id: string; name: string; description?: string; status: string }

const NAV = [
  { to: '/',           icon: LayoutDashboard, label: 'ダッシュボード', end: true },
  { to: '/issues',     icon: ListChecks,      label: '課題一覧',       end: false },
  { to: '/inputs',     icon: History,         label: '要望履歴',       end: true },
  { to: '/inputs/new', icon: PlusCircle,      label: '要望登録',       end: true },
  { to: '/users',      icon: Users,           label: 'ユーザー管理',   end: true },
]

export default function Layout() {
  const [collapsed, setCollapsed] = useState(false)
  const [showModal, setShowModal]  = useState(false)
  const [projects, setProjects]    = useState<Project[]>([])
  const [filtered, setFiltered]    = useState<Project[]>([])
  const [query, setQuery]          = useState('')
  const [currentPJ, setCurrentPJ] = useState<Project | null>(null)
  const [loading, setLoading]      = useState(false)
  const searchRef = useRef<HTMLInputElement>(null)
  const navigate  = useNavigate()

  // 起動時: currentProject を localStorage から復元
  useEffect(() => {
    const id   = localStorage.getItem('current_project_id')
    const name = localStorage.getItem('current_project_name')
    if (id && name) setCurrentPJ({ id, name, status: 'active' })
    else openModal()          // 未選択なら即モーダル表示
  }, [])

  async function openModal() {
    setShowModal(true)
    setQuery('')
    if (projects.length === 0) {
      setLoading(true)
      try {
        const res = await apiClient.get('/projects')
        const list = (res.data as Project[]).filter(p => p.status !== 'archived')
        setProjects(list)
        setFiltered(list)
      } finally { setLoading(false) }
    } else {
      setFiltered(projects)
    }
    setTimeout(() => searchRef.current?.focus(), 80)
  }

  function closeModal() { setShowModal(false); setQuery('') }

  function onQuery(q: string) {
    setQuery(q)
    setFiltered(projects.filter(p =>
      p.name.toLowerCase().includes(q.toLowerCase()) ||
      (p.description || '').toLowerCase().includes(q.toLowerCase())
    ))
  }

  function selectProject(p: Project) {
    localStorage.setItem('current_project_id',   p.id)
    localStorage.setItem('current_project_name', p.name)
    setCurrentPJ(p)
    closeModal()
  }

  function logout() {
    localStorage.removeItem('access_token')
    localStorage.removeItem('refresh_token')
    localStorage.removeItem('current_project_id')
    localStorage.removeItem('current_project_name')
    navigate('/login')
  }

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
        {/* ── Logo ── */}
        <div style={{ padding: '14px 12px 10px', display: 'flex', alignItems: 'center', gap: 8 }}>
          <div style={{
            width: 30, height: 30, borderRadius: 8, flexShrink: 0,
            background: 'linear-gradient(135deg,#6366f1,#8b5cf6)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <Zap size={15} color="#fff" />
          </div>
          <span className="sidebar-label" style={{ fontWeight: 800, fontSize: 14, color: '#fff', letterSpacing: '-0.03em' }}>
            decision-os
          </span>
        </div>

        {/* ── Project Switcher ── */}
        <div style={{ padding: '0 8px 10px' }}>
          <button
            onClick={openModal}
            className="sidebar-label"
            style={{
              width: '100%', display: 'flex', alignItems: 'center', gap: 8,
              padding: '8px 10px', borderRadius: 9,
              background: 'rgba(255,255,255,0.07)',
              border: '1px solid rgba(255,255,255,0.1)',
              cursor: 'pointer', textAlign: 'left',
              transition: 'background 0.15s',
            }}
            onMouseEnter={e => (e.currentTarget.style.background = 'rgba(255,255,255,0.12)')}
            onMouseLeave={e => (e.currentTarget.style.background = 'rgba(255,255,255,0.07)')}
          >
            <FolderOpen size={14} color="#a5b4fc" style={{ flexShrink: 0 }} />
            <span style={{
              flex: 1, fontSize: 12, fontWeight: 600,
              color: currentPJ ? '#e0e4f7' : '#6b7280',
              overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
            }}>
              {currentPJ ? currentPJ.name : 'プロジェクトを選択'}
            </span>
            <ChevronDown size={12} color="rgba(255,255,255,0.35)" style={{ flexShrink: 0 }} />
          </button>
        </div>

        <div style={{ height: 1, background: 'rgba(255,255,255,0.07)', margin: '0 12px 6px' }} />

        {/* ── Nav ── */}
        <nav style={{ flex: 1, padding: '4px 8px', overflowY: 'auto' }}>
          {NAV.map(({ to, icon: Icon, label, end }) => (
            <NavLink
              key={to} to={to} end={end}
              style={({ isActive }) => ({
                display: 'flex', alignItems: 'center', gap: 10,
                padding: '8px 10px', borderRadius: 8, marginBottom: 2,
                color: isActive ? '#fff' : 'rgba(180,188,210,0.85)',
                background: isActive ? 'rgba(99,102,241,0.35)' : 'transparent',
                textDecoration: 'none', fontSize: 13.5,
                fontWeight: isActive ? 600 : 400, transition: 'all 0.15s',
              })}
            >
              <Icon size={17} style={{ flexShrink: 0 }} />
              <span className="sidebar-label">{label}</span>
            </NavLink>
          ))}
        </nav>

        <div style={{ height: 1, background: 'rgba(255,255,255,0.07)', margin: '0 12px 6px' }} />

        {/* ── Bottom ── */}
        <div style={{ padding: '6px 8px 12px', display: 'flex', flexDirection: 'column', gap: 2 }}>
          <ThemeToggle />
          <button onClick={logout} style={{
            display: 'flex', alignItems: 'center', gap: 10,
            padding: '8px 10px', borderRadius: 8, width: '100%',
            background: 'none', border: 'none', cursor: 'pointer',
            color: 'rgba(180,188,210,0.6)', fontSize: 13.5,
          }}>
            <LogOut size={17} style={{ flexShrink: 0 }} />
            <span className="sidebar-label">ログアウト</span>
          </button>
          <button onClick={() => setCollapsed(c => !c)} style={{
            display: 'flex', alignItems: 'center', gap: 10,
            padding: '8px 10px', borderRadius: 8, width: '100%',
            background: 'none', border: 'none', cursor: 'pointer',
            color: 'rgba(180,188,210,0.4)', fontSize: 12,
          }}>
            {collapsed ? <ChevronRight size={15} /> : <ChevronLeft size={15} />}
            <span className="sidebar-label">折りたたむ</span>
          </button>
        </div>
      </aside>

      {/* ── Main ── */}
      <main style={{
        flex: 1,
        marginLeft: collapsed ? 64 : 240,
        transition: 'margin-left 0.25s cubic-bezier(0.4,0,0.2,1)',
        minHeight: '100vh', background: 'var(--bg-main)',
      }}>
        <header style={{
          height: 52, display: 'flex', alignItems: 'center', justifyContent: 'flex-end',
          padding: '0 24px', borderBottom: '1px solid var(--border)',
          background: 'var(--bg-main)', position: 'sticky', top: 0, zIndex: 40,
        }}>
          <GlobalSearch />
          <Bell size={18} style={{ color: 'var(--text-muted)', cursor: 'pointer', marginLeft: 16 }} />
          <div style={{
            marginLeft: 16, width: 32, height: 32, borderRadius: '50%',
            background: 'linear-gradient(135deg,#6366f1,#8b5cf6)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            color: '#fff', fontSize: 13, fontWeight: 700,
          }}>U</div>
        </header>
        <div style={{ padding: '28px 32px' }}>
          <Outlet />
        </div>
      </main>

      {/* ── Project Switch Modal ── */}
      {showModal && (
        <>
          {/* オーバーレイ */}
          <div
            onClick={closeModal}
            style={{
              position: 'fixed', inset: 0, zIndex: 100,
              background: 'rgba(0,0,0,0.45)', backdropFilter: 'blur(2px)',
            }}
          />
          {/* モーダル */}
          <div style={{
            position: 'fixed', top: '15%', left: '50%', transform: 'translateX(-50%)',
            width: '100%', maxWidth: 480, zIndex: 101,
            background: 'var(--bg-surface)',
            border: '1px solid var(--border)',
            borderRadius: 14, boxShadow: '0 24px 64px rgba(0,0,0,0.35)',
            overflow: 'hidden',
          }}>
            {/* モーダルヘッダー */}
            <div style={{
              display: 'flex', alignItems: 'center', justifyContent: 'space-between',
              padding: '16px 18px 12px',
              borderBottom: '1px solid var(--border)',
            }}>
              <span style={{ fontWeight: 700, fontSize: 14, color: 'var(--text-primary)' }}>
                プロジェクトを切り替え
              </span>
              <button onClick={closeModal} style={{
                background: 'none', border: 'none', cursor: 'pointer',
                color: 'var(--text-muted)', padding: 4, borderRadius: 6,
                display: 'flex', alignItems: 'center',
              }}>
                <X size={16} />
              </button>
            </div>

            {/* 検索 */}
            <div style={{ padding: '10px 14px', borderBottom: '1px solid var(--border)' }}>
              <div style={{ position: 'relative' }}>
                <Search size={14} style={{
                  position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)',
                  color: 'var(--text-muted)',
                }} />
                
                  placeholder="プロジェクトを検索..."
                  style={{
                    width: '100%', padding: '8px 12px 8px 32px',
                    borderRadius: 8, fontSize: 13,
                    background: 'var(--bg-muted)',
                    border: '1px solid var(--border)',
                    color: 'var(--text-primary)',
                    outline: 'none',
                  }}
                />
              </div>
            </div>

            {/* プロジェクトリスト */}
            <div style={{ maxHeight: 360, overflowY: 'auto', padding: '6px 8px' }}>
              {loading ? (
                <div style={{ textAlign: 'center', padding: 32, color: 'var(--text-muted)', fontSize: 13 }}>
                  読み込み中...
                </div>
              ) : filtered.length === 0 ? (
                <div style={{ textAlign: 'center', padding: 32, color: 'var(--text-muted)', fontSize: 13 }}>
                  {query ? `"${query}" に一致するプロジェクトなし` : 'プロジェクトがありません'}
                </div>
              ) : filtered.map(p => {
                const isCurrent = currentPJ?.id === p.id
                return (
                  <button
                    key={p.id}
                    onClick={() => selectProject(p)}
                    style={{
                      width: '100%', display: 'flex', alignItems: 'center', gap: 10,
                      padding: '9px 10px', borderRadius: 8, marginBottom: 2,
                      background: isCurrent ? 'rgba(99,102,241,0.1)' : 'transparent',
                      border: 'none', cursor: 'pointer', textAlign: 'left',
                      transition: 'background 0.12s',
                    }}
                    onMouseEnter={e => {
                      if (!isCurrent) (e.currentTarget as HTMLButtonElement).style.background = 'var(--bg-muted)'
                    }}
                    onMouseLeave={e => {
                      if (!isCurrent) (e.currentTarget as HTMLButtonElement).style.background = 'transparent'
                    }}
                  >
                    <div style={{
                      width: 30, height: 30, borderRadius: 7, flexShrink: 0,
                      background: isCurrent ? 'rgba(99,102,241,0.2)' : 'var(--bg-muted)',
                      display: 'flex', alignItems: 'center', justifyContent: 'center',
                    }}>
                      <FolderOpen size={14} color={isCurrent ? '#6366f1' : 'var(--text-muted)'} />
                    </div>
                    <div style={{ flex: 1, overflow: 'hidden' }}>
                      <div style={{
                        fontSize: 13, fontWeight: isCurrent ? 600 : 500,
                        color: isCurrent ? '#6366f1' : 'var(--text-primary)',
                        overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
                      }}>
                        {p.name}
                      </div>
                      {p.description && (
                        <div style={{
                          fontSize: 11, color: 'var(--text-muted)',
                          overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
                        }}>
                          {p.description}
                        </div>
                      )}
                    </div>
                    {isCurrent && <Check size={14} color="#6366f1" style={{ flexShrink: 0 }} />}
                  </button>
                )
              })}
            </div>

            {/* フッター */}
            <div style={{
              padding: '10px 14px',
              borderTop: '1px solid var(--border)',
              fontSize: 11, color: 'var(--text-muted)',
            }}>
              {filtered.length}件のプロジェクト
            </div>
          </div>
        </>
      )}
    </div>
  )
}
