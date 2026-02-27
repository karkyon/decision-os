#!/usr/bin/env bash
# =============================================================================
# 39_fix_all_ts.sh — TSビルドエラー全件修正
#   - App.tsx: JSX親要素エラー
#   - Layout.tsx: 構文エラー
#   - IssueDetail.tsx: JSX構造が壊れている → 完全書き直し
# =============================================================================
set -euo pipefail
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BOLD='\033[1m'; CYAN='\033[0;36m'; RESET='\033[0m'
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

FRONTEND="$HOME/projects/decision-os/frontend"
SRC="$FRONTEND/src"
TS=$(date +%Y%m%d_%H%M%S)
BACKUP="$HOME/projects/decision-os/backup_ts_$TS"
mkdir -p "$BACKUP"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
nvm use 20 2>/dev/null || true

# =============================================================================
section "0. 壊れたファイルをバックアップ"
# =============================================================================
cp "$SRC/App.tsx"                "$BACKUP/" 2>/dev/null || true
cp "$SRC/components/Layout.tsx"  "$BACKUP/" 2>/dev/null || true
cp "$SRC/pages/IssueDetail.tsx"  "$BACKUP/" 2>/dev/null || true
ok "バックアップ: $BACKUP"

# =============================================================================
section "1. App.tsx 修正（JSX親要素エラー）"
# =============================================================================
info "App.tsx 現在の内容 (15-35行):"
sed -n '15,35p' "$SRC/App.tsx" || true

# App.tsx の実態に合わせてRoutes構造を修正
python3 << 'PYEOF'
import os, re

path = os.path.expanduser(
    "~/projects/decision-os/frontend/src/App.tsx"
)
with open(path) as f:
    content = f.read()

# JSX親要素エラーの典型パターン: Routes の外に要素が漏れている
# 修正: 全体を <> ... </> で囲む or Routes内に収める

# 既に修正済みか確認
if content.count('<Routes>') == 1 and 'TS2657' not in content:
    print("  変更不要（既に正常）")
else:
    # Routeが複数の親要素を持つパターンを修正
    # 典型: return ( <Route .../> <Route .../> ) → return ( <Routes> <Route.../> </Routes> )
    print(f"  App.tsx の Routes 構造を確認:")
    for i, line in enumerate(content.split('\n')[14:30], 15):
        print(f"    {i}: {line}")
PYEOF

# App.tsx を安全な構造に書き直す
cat > "$SRC/App.tsx" << 'APPEOF'
import { Routes, Route, Navigate } from 'react-router-dom'
import { useAuthStore } from './store/auth'
import Login from './pages/Login'
import Dashboard from './pages/Dashboard'
import InputNew from './pages/InputNew'
import IssueList from './pages/IssueList'
import IssueDetail from './pages/IssueDetail'
import Layout from './components/Layout'

function PrivateRoute({ children }: { children: React.ReactNode }) {
  const { token } = useAuthStore()
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
        <Route path="inputs/new" element={<InputNew />} />
        <Route path="issues" element={<IssueList />} />
        <Route path="issues/:id" element={<IssueDetail />} />
      </Route>
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  )
}
APPEOF
ok "App.tsx 修正完了"

# =============================================================================
section "2. Layout.tsx 修正（構文エラー line 14）"
# =============================================================================
info "Layout.tsx 現在の内容 (10-20行):"
sed -n '10,20p' "$SRC/components/Layout.tsx" || true

python3 << 'PYEOF'
import os, re

path = os.path.expanduser(
    "~/projects/decision-os/frontend/src/components/Layout.tsx"
)
if not os.path.exists(path):
    print("  Layout.tsx が見つかりません")
    exit()

with open(path) as f:
    content = f.read()

print("  Layout.tsx 全文:")
for i, line in enumerate(content.split('\n'), 1):
    print(f"    {i:3d}: {line}")
PYEOF

# Layout.tsx を正常な構造で書き直し
cat > "$SRC/components/Layout.tsx" << 'LAYOUTEOF'
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
LAYOUTEOF
ok "Layout.tsx 修正完了"

# =============================================================================
section "3. IssueDetail.tsx 完全書き直し（JSX構造崩壊を修正）"
# =============================================================================
info "IssueDetail.tsx のエラー行数を確認:"
wc -l "$SRC/pages/IssueDetail.tsx" || true
info "エラーが100件以上 → JSX構造が根本的に壊れているため完全書き直し"

cat > "$SRC/pages/IssueDetail.tsx" << 'ISSUEEOF'
import { useState, useEffect } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { useAuthStore } from '../store/auth'

interface Issue {
  id: string
  title: string
  description?: string
  status: string
  priority: string
  assignee_id?: string
  labels?: string
  created_at: string
  updated_at?: string
}

interface TraceItem {
  id: string
  text: string
  intent_code: string
  domain_code: string
  confidence: number
}

interface TraceInput {
  id: string
  source_type: string
  raw_text: string
  created_at: string
}

interface TraceData {
  issue: Issue
  action?: { id: string; action_type: string; decision_reason?: string }
  item?: TraceItem
  input?: TraceInput
}

const STATUS_LABELS: Record<string, string> = {
  open: '未着手',
  in_progress: '作業中',
  review: 'レビュー',
  done: '完了',
  hold: '保留',
}

const PRIORITY_LABELS: Record<string, string> = {
  low: '低',
  medium: '中',
  high: '高',
  critical: '緊急',
}

const PRIORITY_COLORS: Record<string, string> = {
  low: '#6b7280',
  medium: '#f59e0b',
  high: '#ef4444',
  critical: '#7c3aed',
}

export default function IssueDetail() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { token } = useAuthStore()

  const [issue, setIssue] = useState<Issue | null>(null)
  const [trace, setTrace] = useState<TraceData | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [editStatus, setEditStatus] = useState('')
  const [saving, setSaving] = useState(false)
  const [activeTab, setActiveTab] = useState<'detail' | 'trace'>('detail')

  const headers = {
    'Content-Type': 'application/json',
    Authorization: `Bearer ${token}`,
  }

  useEffect(() => {
    if (!id) return
    fetchIssue()
    fetchTrace()
  }, [id])

  async function fetchIssue() {
    try {
      const res = await fetch(`/api/v1/issues/${id}`, { headers })
      if (!res.ok) throw new Error('取得失敗')
      const data = await res.json()
      setIssue(data)
      setEditStatus(data.status)
    } catch (e) {
      setError('課題の取得に失敗しました')
    } finally {
      setLoading(false)
    }
  }

  async function fetchTrace() {
    try {
      const res = await fetch(`/api/v1/trace/${id}`, { headers })
      if (res.ok) {
        const data = await res.json()
        setTrace(data)
      }
    } catch {
      // トレースは任意なのでエラー無視
    }
  }

  async function handleStatusChange(newStatus: string) {
    if (!id) return
    setSaving(true)
    try {
      const res = await fetch(`/api/v1/issues/${id}`, {
        method: 'PATCH',
        headers,
        body: JSON.stringify({ status: newStatus }),
      })
      if (!res.ok) throw new Error('更新失敗')
      const updated = await res.json()
      setIssue(updated)
      setEditStatus(updated.status)
    } catch {
      setError('ステータスの更新に失敗しました')
    } finally {
      setSaving(false)
    }
  }

  if (loading) {
    return (
      <div style={{ display: 'flex', justifyContent: 'center', padding: '60px' }}>
        <div style={{ color: '#6b7280' }}>読み込み中...</div>
      </div>
    )
  }

  if (error || !issue) {
    return (
      <div style={{ padding: '32px' }}>
        <div style={{ color: '#ef4444', marginBottom: '16px' }}>{error || '課題が見つかりません'}</div>
        <button onClick={() => navigate('/issues')} style={btnStyle}>← 一覧に戻る</button>
      </div>
    )
  }

  return (
    <div style={{ maxWidth: '900px' }}>
      {/* ヘッダー */}
      <div style={{ display: 'flex', alignItems: 'center', gap: '16px', marginBottom: '24px' }}>
        <button onClick={() => navigate('/issues')} style={backBtnStyle}>
          ← 一覧
        </button>
        <h1 style={{ fontSize: '22px', fontWeight: 700, color: '#1e293b', margin: 0, flex: 1 }}>
          {issue.title}
        </h1>
        <span style={{
          padding: '4px 12px',
          borderRadius: '999px',
          background: PRIORITY_COLORS[issue.priority] + '20',
          color: PRIORITY_COLORS[issue.priority],
          fontSize: '13px',
          fontWeight: 600,
        }}>
          {PRIORITY_LABELS[issue.priority] || issue.priority}
        </span>
      </div>

      {/* タブ */}
      <div style={{ display: 'flex', gap: '4px', marginBottom: '24px', borderBottom: '2px solid #e2e8f0' }}>
        {(['detail', 'trace'] as const).map((tab) => (
          <button
            key={tab}
            onClick={() => setActiveTab(tab)}
            style={{
              padding: '10px 20px',
              border: 'none',
              background: 'none',
              cursor: 'pointer',
              fontWeight: activeTab === tab ? 700 : 400,
              color: activeTab === tab ? '#3b82f6' : '#6b7280',
              borderBottom: activeTab === tab ? '2px solid #3b82f6' : '2px solid transparent',
              marginBottom: '-2px',
            }}
          >
            {tab === 'detail' ? '詳細' : 'トレーサビリティ'}
          </button>
        ))}
      </div>

      {/* 詳細タブ */}
      {activeTab === 'detail' && (
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 280px', gap: '24px' }}>
          {/* 左カラム */}
          <div>
            <div style={cardStyle}>
              <h3 style={cardTitleStyle}>説明</h3>
              <p style={{ color: '#475569', lineHeight: 1.7, margin: 0 }}>
                {issue.description || '（説明なし）'}
              </p>
            </div>
          </div>

          {/* 右カラム */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
            <div style={cardStyle}>
              <h3 style={cardTitleStyle}>ステータス</h3>
              <select
                value={editStatus}
                onChange={(e) => {
                  setEditStatus(e.target.value)
                  handleStatusChange(e.target.value)
                }}
                disabled={saving}
                style={selectStyle}
              >
                {Object.entries(STATUS_LABELS).map(([val, label]) => (
                  <option key={val} value={val}>{label}</option>
                ))}
              </select>
            </div>

            <div style={cardStyle}>
              <h3 style={cardTitleStyle}>優先度</h3>
              <span style={{ color: PRIORITY_COLORS[issue.priority], fontWeight: 600 }}>
                {PRIORITY_LABELS[issue.priority] || issue.priority}
              </span>
            </div>

            <div style={cardStyle}>
              <h3 style={cardTitleStyle}>ラベル</h3>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px' }}>
                {issue.labels
                  ? issue.labels.split(',').map((l) => (
                      <span key={l} style={tagStyle}>{l.trim()}</span>
                    ))
                  : <span style={{ color: '#94a3b8', fontSize: '13px' }}>なし</span>
                }
              </div>
            </div>

            <div style={cardStyle}>
              <h3 style={cardTitleStyle}>作成日時</h3>
              <span style={{ color: '#475569', fontSize: '13px' }}>
                {new Date(issue.created_at).toLocaleString('ja-JP')}
              </span>
            </div>
          </div>
        </div>
      )}

      {/* トレーサビリティタブ */}
      {activeTab === 'trace' && (
        <div>
          {trace ? (
            <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
              {/* 課題 */}
              <TraceNode
                label="課題 (ISSUE)"
                color="#3b82f6"
                content={trace.issue.title}
              />

              {/* アクション */}
              {trace.action && (
                <>
                  <TraceArrow />
                  <TraceNode
                    label="対応判断 (ACTION)"
                    color="#8b5cf6"
                    content={trace.action.action_type}
                    sub={trace.action.decision_reason}
                  />
                </>
              )}

              {/* アイテム */}
              {trace.item && (
                <>
                  <TraceArrow />
                  <TraceNode
                    label={`分解単位 (ITEM) — ${trace.item.intent_code} / ${trace.item.domain_code}`}
                    color="#10b981"
                    content={trace.item.text}
                    sub={`信頼度: ${Math.round(trace.item.confidence * 100)}%`}
                  />
                </>
              )}

              {/* 原文 */}
              {trace.input && (
                <>
                  <TraceArrow />
                  <TraceNode
                    label={`原文 (INPUT) — ${trace.input.source_type} / ${new Date(trace.input.created_at).toLocaleDateString('ja-JP')}`}
                    color="#f59e0b"
                    content={trace.input.raw_text}
                  />
                </>
              )}
            </div>
          ) : (
            <div style={{ color: '#94a3b8', padding: '32px', textAlign: 'center' }}>
              トレースデータがありません
            </div>
          )}
        </div>
      )}
    </div>
  )
}

// ── サブコンポーネント ────────────────────────────────────────────────────────

function TraceNode({ label, color, content, sub }: {
  label: string
  color: string
  content: string
  sub?: string
}) {
  return (
    <div style={{
      border: `2px solid ${color}30`,
      borderLeft: `4px solid ${color}`,
      borderRadius: '8px',
      padding: '16px',
      background: '#fff',
    }}>
      <div style={{ fontSize: '12px', fontWeight: 700, color, marginBottom: '8px', textTransform: 'uppercase', letterSpacing: '0.05em' }}>
        {label}
      </div>
      <div style={{ color: '#1e293b', lineHeight: 1.6 }}>{content}</div>
      {sub && <div style={{ color: '#94a3b8', fontSize: '13px', marginTop: '6px' }}>{sub}</div>}
    </div>
  )
}

function TraceArrow() {
  return (
    <div style={{ display: 'flex', justifyContent: 'center', color: '#cbd5e1', fontSize: '20px' }}>
      ↑
    </div>
  )
}

// ── スタイル定数 ──────────────────────────────────────────────────────────────

const cardStyle: React.CSSProperties = {
  background: '#fff',
  border: '1px solid #e2e8f0',
  borderRadius: '8px',
  padding: '16px',
}

const cardTitleStyle: React.CSSProperties = {
  fontSize: '12px',
  fontWeight: 700,
  color: '#94a3b8',
  textTransform: 'uppercase',
  letterSpacing: '0.05em',
  marginBottom: '10px',
  margin: '0 0 10px 0',
}

const btnStyle: React.CSSProperties = {
  padding: '8px 16px',
  background: '#3b82f6',
  color: '#fff',
  border: 'none',
  borderRadius: '6px',
  cursor: 'pointer',
  fontWeight: 600,
}

const backBtnStyle: React.CSSProperties = {
  padding: '6px 14px',
  background: '#f1f5f9',
  color: '#475569',
  border: '1px solid #e2e8f0',
  borderRadius: '6px',
  cursor: 'pointer',
}

const selectStyle: React.CSSProperties = {
  width: '100%',
  padding: '8px',
  border: '1px solid #e2e8f0',
  borderRadius: '6px',
  background: '#f8fafc',
  color: '#1e293b',
  cursor: 'pointer',
}

const tagStyle: React.CSSProperties = {
  padding: '2px 10px',
  background: '#eff6ff',
  color: '#3b82f6',
  borderRadius: '999px',
  fontSize: '12px',
  fontWeight: 600,
}
ISSUEEOF
ok "IssueDetail.tsx 完全書き直し完了"

# =============================================================================
section "4. ビルド確認"
# =============================================================================
cd "$FRONTEND"
info "npm run build 実行中..."
BUILD_OUT=$(npm run build 2>&1)
BUILD_EXIT=$?

echo "$BUILD_OUT" | tail -20

echo ""
if [[ $BUILD_EXIT -eq 0 ]]; then
    ok "🎉 ビルド成功！ TSエラー完全解消"
else
    warn "残りエラー:"
    echo "$BUILD_OUT" | grep "error TS" | head -20
fi

# =============================================================================
section "5. #2 課題一覧バグ診断 — API・フロント確認"
# =============================================================================
cd "$HOME/projects/decision-os/backend"
source .venv/bin/activate

# バックエンド起動確認
if ! curl -s http://localhost:8089/docs > /dev/null 2>&1; then
    warn "バックエンドが停止中 → 再起動します"
    pkill -f uvicorn 2>/dev/null || true; sleep 1
    nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
      > ~/projects/decision-os/logs/backend.log 2>&1 &
    sleep 4
fi

# ログイン
TOKEN=$(curl -s -X POST http://localhost:8089/api/v1/auth/login \
    -H "Content-Type: application/json" \
    -d '{"email":"demo@example.com","password":"demo1234"}' \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('access_token',''))" 2>/dev/null || echo "")

if [[ -z "$TOKEN" ]]; then
    warn "ログイン失敗 → デモアカウントがない可能性"
    # アカウント作成
    info "デモアカウント作成を試みます..."
    curl -s -X POST http://localhost:8089/api/v1/auth/register \
        -H "Content-Type: application/json" \
        -d '{"name":"Demo User","email":"demo@example.com","password":"demo1234","role":"pm"}' \
        | python3 -m json.tool 2>/dev/null || true

    TOKEN=$(curl -s -X POST http://localhost:8089/api/v1/auth/login \
        -H "Content-Type: application/json" \
        -d '{"email":"demo@example.com","password":"demo1234"}' \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('access_token',''))" 2>/dev/null || echo "")
fi

if [[ -n "$TOKEN" ]]; then
    info "ログイン成功 → データ確認:"

    echo ""
    info "▼ Projects:"
    curl -s http://localhost:8089/api/v1/projects \
        -H "Authorization: Bearer $TOKEN" \
        | python3 -c "import sys,json; d=json.load(sys.stdin); [print(f'  id={p[\"id\"]} name={p[\"name\"]}') for p in (d if isinstance(d,list) else d.get('items',[]))]" 2>/dev/null || echo "  (なし)"

    echo ""
    info "▼ Actions (最新5件):"
    curl -s "http://localhost:8089/api/v1/actions?limit=5" \
        -H "Authorization: Bearer $TOKEN" \
        | python3 -c "
import sys,json
d=json.load(sys.stdin)
items = d if isinstance(d,list) else d.get('items',[])
for a in items[:5]:
    print(f'  id={a[\"id\"]} type={a[\"action_type\"]} item_id={a[\"item_id\"]}')
if not items:
    print('  (なし)')
" 2>/dev/null || echo "  (レスポンスなし)"

    echo ""
    info "▼ Issues (最新5件):"
    curl -s "http://localhost:8089/api/v1/issues?limit=5" \
        -H "Authorization: Bearer $TOKEN" \
        | python3 -c "
import sys,json
d=json.load(sys.stdin)
items = d if isinstance(d,list) else d.get('items',[])
for i in items[:5]:
    print(f'  id={i[\"id\"]} title={i[\"title\"][:40]} status={i[\"status\"]}')
if not items:
    print('  (なし) ← これが問題の可能性')
" 2>/dev/null || echo "  (レスポンスなし)"

    echo ""
    info "▼ actions.py の Issue自動生成ロジック確認:"
    grep -n "Issue\|CREATE_ISSUE\|issue" \
        "$HOME/projects/decision-os/backend/app/api/v1/routers/actions.py" \
        | head -20 || echo "  (actions.py が見つからない)"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  39_fix_all_ts.sh 完了"
echo ""
echo "  ✅ ビルド成功なら → 結果を貼ってください（#2バグ修正へ）"
echo "  ❌ エラー残りなら → エラー行を貼ってください"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
