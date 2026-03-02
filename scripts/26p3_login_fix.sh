#!/usr/bin/env bash
# =============================================================================
# decision-os / 26p3: ログイン修正（email フィールド + JSON）
# =============================================================================
set -euo pipefail
GREEN='\033[0;32m'; BOLD='\033[1m'; RESET='\033[0m'
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

FRONTEND="$HOME/projects/decision-os/frontend/src"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
nvm use 20 2>/dev/null || true

# ---------- 動作確認（email + JSON） ----------
section "API確認"
echo "--- POST /auth/login {email, password} ---"
curl -s -X POST http://localhost:8089/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo1234"}' | python3 -m json.tool

# ---------- Login.tsx 修正 ----------
section "Login.tsx 修正"
cat > "$FRONTEND/pages/Login.tsx" << 'TSX'
import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Zap, Loader2 } from 'lucide-react'
import apiClient from '@/api/client'

export default function Login() {
  const [email, setEmail]       = useState('demo@example.com')
  const [password, setPassword] = useState('demo1234')
  const [error, setError]       = useState('')
  const [loading, setLoading]   = useState(false)
  const navigate = useNavigate()

  async function handleLogin() {
    setLoading(true); setError('')
    try {
      // バックエンドは { email, password } の JSON を期待
      const res = await apiClient.post('/auth/login', { email, password })
      const token = res.data.access_token
      if (!token) throw new Error('トークンが取得できませんでした')
      localStorage.setItem('access_token', token)
      navigate('/')
    } catch (e: unknown) {
      const detail = (e as { response?: { data?: { detail?: string } } })?.response?.data?.detail
      setError(typeof detail === 'string' ? detail : 'ログインに失敗しました。メールとパスワードを確認してください。')
    } finally {
      setLoading(false)
    }
  }

  const inputStyle: React.CSSProperties = {
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
          type="email" value={email}
          onChange={e => setEmail(e.target.value)}
          placeholder="メールアドレス" style={inputStyle}
        />
        <input
          type="password" value={password}
          onChange={e => setPassword(e.target.value)}
          placeholder="パスワード" style={inputStyle}
          onKeyDown={e => e.key === 'Enter' && handleLogin()}
        />

        {error && (
          <div style={{
            background: 'rgba(239,68,68,0.1)', border: '1px solid rgba(239,68,68,0.3)',
            borderRadius: 6, padding: '8px 12px', marginBottom: 12,
            color: '#f87171', fontSize: 12,
          }}>
            {error}
          </div>
        )}

        <button
          onClick={handleLogin}
          disabled={loading}
          style={{
            width: '100%', padding: '11px', borderRadius: 8, border: 'none',
            background: 'linear-gradient(135deg, #6366f1, #8b5cf6)',
            color: '#fff', fontWeight: 600, fontSize: 14,
            cursor: loading ? 'not-allowed' : 'pointer',
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6,
            opacity: loading ? 0.7 : 1,
          }}
        >
          {loading
            ? <><Loader2 size={15} style={{ animation: 'spin 1s linear infinite' }} />ログイン中...</>
            : 'ログイン'}
        </button>
        <style>{`@keyframes spin { to { transform: rotate(360deg) } }`}</style>
      </div>
    </div>
  )
}
TSX

echo -e "${GREEN}[OK]    Login.tsx 修正完了${RESET}"

# ---------- 型チェック ----------
section "型チェック"
cd "$HOME/projects/decision-os/frontend"
npm run typecheck && echo -e "${GREEN}[OK]    型チェック PASS${RESET}" || echo "[WARN]  型警告あり（続行）"

# ---------- 再起動 ----------
section "フロントエンド再起動"
PID=$(lsof -ti :3008 2>/dev/null || true)
[ -n "$PID" ] && kill "$PID" 2>/dev/null && sleep 2

nohup npm run dev -- --host 0.0.0.0 --port 3008 \
  > "$HOME/projects/decision-os/logs/frontend.log" 2>&1 &
sleep 3

lsof -ti :3008 &>/dev/null \
  && echo -e "${GREEN}[OK]    http://localhost:3008 起動完了${RESET}" \
  || echo "[WARN]  ログ確認: tail -f ~/projects/decision-os/logs/frontend.log"
