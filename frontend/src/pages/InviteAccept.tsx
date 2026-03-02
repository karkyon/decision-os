import { useEffect, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { Zap, Loader2, CheckCircle, XCircle, Eye, EyeOff } from 'lucide-react'
import apiClient from '@/api/client'
import ThemeToggle from '@/components/ThemeToggle'

interface InviteInfo {
  email: string
  role: string
  tenant_name: string
  expires_at: string
}

export default function InviteAccept() {
  const [params] = useSearchParams()
  const token = params.get('token') || ''
  const navigate = useNavigate()

  const [step, setStep]         = useState<'loading'|'form'|'done'|'error'>('loading')
  const [info, setInfo]         = useState<InviteInfo | null>(null)
  const [errorMsg, setErrorMsg] = useState('')
  const [name, setName]         = useState('')
  const [password, setPassword] = useState('')
  const [showPw, setShowPw]     = useState(false)
  const [submitting, setSubmitting] = useState(false)

  useEffect(() => {
    if (!token) { setErrorMsg('招待トークンがありません'); setStep('error'); return }
    apiClient.get(`/auth/invite/${token}`)
      .then(res => { setInfo(res.data); setStep('form') })
      .catch(err => {
        setErrorMsg(err.response?.data?.detail || '招待リンクが無効または期限切れです')
        setStep('error')
      })
  }, [token])

  async function handleSubmit() {
    if (!name.trim()) return
    if (password.length < 8) return
    setSubmitting(true)
    try {
      const res = await apiClient.post('/auth/invite/accept', { token, name, password })
      localStorage.setItem('access_token',  res.data.access_token)
      localStorage.setItem('refresh_token', res.data.refresh_token)
      setStep('done')
      setTimeout(() => navigate('/workspaces'), 2000)
    } catch (err: any) {
      setErrorMsg(err.response?.data?.detail || 'アカウント作成に失敗しました')
      setStep('error')
    } finally {
      setSubmitting(false)
    }
  }

  const ROLE_LABEL: Record<string, string> = {
    admin: '管理者', pm: 'PM', dev: '開発者', viewer: '閲覧者',
  }

  return (
    <div style={{
      minHeight: '100vh', background: 'var(--bg-base)',
      display: 'flex', flexDirection: 'column',
      alignItems: 'center', justifyContent: 'center',
      padding: '24px 16px', position: 'relative',
    }}>
      <div style={{
        position: 'fixed', top: 0, left: 0, right: 0, height: 3,
        background: 'linear-gradient(90deg,#6366f1,#8b5cf6,#ec4899)',
      }} />
      <div style={{ position: 'fixed', top: 12, right: 16 }}>
        <ThemeToggle />
      </div>

      {/* ロゴ */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 32 }}>
        <div style={{
          width: 36, height: 36, borderRadius: 10,
          background: 'linear-gradient(135deg,#6366f1,#8b5cf6)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <Zap size={18} color="#fff" />
        </div>
        <span style={{ fontWeight: 800, fontSize: 18, color: 'var(--text-primary)', letterSpacing: '-0.04em' }}>
          decision-os
        </span>
      </div>

      <div className="card" style={{ width: '100%', maxWidth: 420, padding: '32px 28px' }}>

        {/* ローディング */}
        {step === 'loading' && (
          <div style={{ textAlign: 'center', padding: '24px 0' }}>
            <Loader2 size={28} style={{ animation: 'spin 1s linear infinite', color: '#6366f1' }} />
            <p style={{ marginTop: 12, color: 'var(--text-muted)', fontSize: 14 }}>招待情報を確認中...</p>
          </div>
        )}

        {/* エラー */}
        {step === 'error' && (
          <div style={{ textAlign: 'center', padding: '16px 0' }}>
            <XCircle size={40} color="#ef4444" style={{ marginBottom: 12 }} />
            <h3 style={{ margin: '0 0 8px', color: 'var(--text-primary)', fontSize: 16, fontWeight: 700 }}>
              招待リンクが無効です
            </h3>
            <p style={{ margin: '0 0 20px', color: 'var(--text-muted)', fontSize: 13 }}>{errorMsg}</p>
            <button
              onClick={() => navigate('/login')}
              style={{
                padding: '8px 20px', borderRadius: 8, border: 'none', cursor: 'pointer',
                background: '#6366f1', color: '#fff', fontSize: 13, fontWeight: 600,
              }}
            >
              ログインページへ
            </button>
          </div>
        )}

        {/* フォーム */}
        {step === 'form' && info && (
          <>
            <h2 style={{ margin: '0 0 4px', fontSize: 20, fontWeight: 800, color: 'var(--text-primary)', letterSpacing: '-0.04em' }}>
              招待を受け入れる
            </h2>
            <p style={{ margin: '0 0 20px', fontSize: 13, color: 'var(--text-muted)' }}>
              アカウントを作成してワークスペースに参加します
            </p>

            {/* 招待情報バッジ */}
            <div style={{
              padding: '12px 14px', borderRadius: 10, marginBottom: 24,
              background: 'rgba(99,102,241,0.08)',
              border: '1px solid rgba(99,102,241,0.2)',
            }}>
              <div style={{ fontSize: 12, color: 'var(--text-muted)', marginBottom: 4 }}>招待先</div>
              <div style={{ fontWeight: 700, fontSize: 14, color: 'var(--text-primary)' }}>{info.tenant_name}</div>
              <div style={{ fontSize: 12, color: '#6366f1', marginTop: 4 }}>
                {info.email} · {ROLE_LABEL[info.role] || info.role}
              </div>
            </div>

            {/* 名前 */}
            <div style={{ marginBottom: 14 }}>
              <label style={{ display: 'block', fontSize: 12, fontWeight: 600, color: 'var(--text-secondary)', marginBottom: 6 }}>
                表示名
              </label>
              <input
                value={name}
                onChange={e => setName(e.target.value)}
                placeholder="山田 太郎"
                autoFocus
                style={{
                  width: '100%', padding: '10px 12px', borderRadius: 8, fontSize: 14,
                  background: 'var(--bg-input)', border: '1px solid var(--border)',
                  color: 'var(--text-primary)', outline: 'none',
                }}
              />
            </div>

            {/* メール（読み取り専用） */}
            <div style={{ marginBottom: 14 }}>
              <label style={{ display: 'block', fontSize: 12, fontWeight: 600, color: 'var(--text-secondary)', marginBottom: 6 }}>
                メールアドレス
              </label>
              <input
                value={info.email}
                readOnly
                style={{
                  width: '100%', padding: '10px 12px', borderRadius: 8, fontSize: 14,
                  background: 'var(--bg-muted)', border: '1px solid var(--border)',
                  color: 'var(--text-muted)', outline: 'none',
                }}
              />
            </div>

            {/* パスワード */}
            <div style={{ marginBottom: 24 }}>
              <label style={{ display: 'block', fontSize: 12, fontWeight: 600, color: 'var(--text-secondary)', marginBottom: 6 }}>
                パスワード（8文字以上）
              </label>
              <div style={{ position: 'relative' }}>
                <input
                  type={showPw ? 'text' : 'password'}
                  value={password}
                  onChange={e => setPassword(e.target.value)}
                  onKeyDown={e => e.key === 'Enter' && handleSubmit()}
                  placeholder="••••••••"
                  style={{
                    width: '100%', padding: '10px 40px 10px 12px', borderRadius: 8, fontSize: 14,
                    background: 'var(--bg-input)', border: '1px solid var(--border)',
                    color: 'var(--text-primary)', outline: 'none',
                  }}
                />
                <button
                  onClick={() => setShowPw(s => !s)}
                  style={{
                    position: 'absolute', right: 10, top: '50%', transform: 'translateY(-50%)',
                    background: 'none', border: 'none', cursor: 'pointer',
                    color: 'var(--text-muted)', padding: 4,
                  }}
                >
                  {showPw ? <EyeOff size={16} /> : <Eye size={16} />}
                </button>
              </div>
              {password.length > 0 && password.length < 8 && (
                <p style={{ margin: '4px 0 0', fontSize: 11, color: '#ef4444' }}>8文字以上で入力してください</p>
              )}
            </div>

            <button
              onClick={handleSubmit}
              disabled={submitting || !name.trim() || password.length < 8}
              style={{
                width: '100%', padding: '11px', borderRadius: 9, border: 'none',
                background: (submitting || !name.trim() || password.length < 8)
                  ? 'var(--bg-muted)' : 'linear-gradient(135deg,#6366f1,#8b5cf6)',
                color: '#fff', fontSize: 14, fontWeight: 700, cursor: 'pointer',
                display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
              }}
            >
              {submitting
                ? <><Loader2 size={16} style={{ animation: 'spin 1s linear infinite' }} /> 作成中...</>
                : 'アカウントを作成して参加'
              }
            </button>
          </>
        )}

        {/* 完了 */}
        {step === 'done' && (
          <div style={{ textAlign: 'center', padding: '16px 0' }}>
            <CheckCircle size={40} color="#22c55e" style={{ marginBottom: 12 }} />
            <h3 style={{ margin: '0 0 8px', color: 'var(--text-primary)', fontSize: 16, fontWeight: 700 }}>
              参加完了！
            </h3>
            <p style={{ margin: 0, color: 'var(--text-muted)', fontSize: 13 }}>
              ワークスペースに移動します...
            </p>
          </div>
        )}
      </div>
      <style>{`@keyframes spin { to { transform: rotate(360deg) } }`}</style>
    </div>
  )
}
