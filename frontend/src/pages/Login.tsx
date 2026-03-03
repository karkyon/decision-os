import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Zap, Loader2 } from 'lucide-react'
import apiClient from '@/api/client'
import ThemeToggle from '@/components/ThemeToggle'

export default function Login() {
  const [email, setEmail]       = useState('demo@example.com')
  const [password, setPassword] = useState('demo1234')
  const [rememberMe, setRememberMe] = useState(() => !!localStorage.getItem("remembered_email"))
  const [error, setError]       = useState('')
  const [loading, setLoading]   = useState(false)
  const navigate = useNavigate()

  async function handleLogin() {
    setLoading(true); setError('')
    try {
      const res = await apiClient.post('/auth/login', { email, password })
      const token = res.data.access_token
      if (!token) throw new Error('no token')
      if (rememberMe) localStorage.setItem("remembered_email", email); else localStorage.removeItem("remembered_email");
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
              {/* ユーザー名を記憶 */}
              <label style={{
                display: 'flex', alignItems: 'center', gap: 8,
                fontSize: 13, color: 'var(--text-secondary)', cursor: 'pointer',
                marginTop: 4,
              }}>
                <input
                  type="checkbox"
                  checked={rememberMe}
                  onChange={e => setRememberMe(e.target.checked)}
                  style={{
                    width: 15, height: 15, cursor: 'pointer',
                    accentColor: 'var(--accent)',
                    border: '1.5px solid var(--border-input)',
                  }}
                />
                メールアドレスを記憶する
              </label>
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
