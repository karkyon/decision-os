import { Outlet, NavLink } from 'react-router-dom'
import { useAuthStore } from '../store/auth'

export default function Layout() {
  const { logout } = useAuthStore()

  return (
    <div style={{ display: 'flex', minHeight: '100vh' }}>
      {/* サイドバー */}
      <nav style={{
        width: '220px',
        background: '#1e293b',
        color: '#fff',
        padding: '24px 0',
        flexShrink: 0,
      }}>
        <div style={{ padding: '0 20px 24px', fontSize: '18px', fontWeight: 700, color: '#60a5fa' }}>
          decision-os
        </div>
        <NavLink
          to="/"
          end
          style={({ isActive }) => navStyle(isActive)}
        >
          ダッシュボード
        </NavLink>
        <NavLink
          to="/inputs/new"
          style={({ isActive }) => navStyle(isActive)}
        >
          要望登録
        </NavLink>
        <NavLink
          to="/issues"
          style={({ isActive }) => navStyle(isActive)}
        >
          課題一覧
        </NavLink>
        <div style={{ marginTop: 'auto', padding: '20px' }}>
          <button
            onClick={logout}
            style={{
              width: '100%', padding: '8px', background: '#334155',
              color: '#fff', border: 'none', borderRadius: '6px', cursor: 'pointer',
            }}
          >
            ログアウト
          </button>
        </div>
      </nav>

      {/* メインコンテンツ */}
      <main style={{ flex: 1, padding: '32px', background: '#f8fafc', overflowY: 'auto' }}>
        <Outlet />
      </main>
    </div>
  )
}

function navStyle(isActive: boolean) {
  return {
    display: 'block',
    padding: '12px 20px',
    color: isActive ? '#60a5fa' : '#cbd5e1',
    textDecoration: 'none',
    background: isActive ? '#0f172a' : 'transparent',
    fontWeight: isActive ? 600 : 400,
  }
}
