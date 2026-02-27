#!/usr/bin/env bash
# =============================================================================
# decision-os / 40_build_check_and_fix.sh
# #1 TSビルドエラー確認・修正
# #2 課題一覧バグ診断（STEP3保存後にIssueが表示されない）
# =============================================================================
set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
FRONTEND_DIR="$PROJECT_DIR/frontend"
BACKEND_DIR="$PROJECT_DIR/backend"
SRC="$FRONTEND_DIR/src"

cd "$FRONTEND_DIR"
eval "$(~/.nvm/nvm.sh 2>/dev/null || true)"
nvm use --lts 2>/dev/null || true

# =============================================================================
section "1. 現在のTSビルドエラー確認"
# =============================================================================
BUILD_OUT=$(npm run build 2>&1 || true)
TS_ERRORS=$(echo "$BUILD_OUT" | grep "error TS" || true)

if [[ -z "$TS_ERRORS" ]]; then
  success "TSビルドエラーなし！ビルド成功 ✅"
  echo "$BUILD_OUT" | tail -5
else
  error "TSエラーあり:"
  echo "$TS_ERRORS"
  echo ""
  info "エラーファイル一覧:"
  echo "$TS_ERRORS" | grep -oP 'src/[^(]+' | sort -u

  # =============================================================================
  section "1-A. 各エラーファイルの内容確認と自動修正"
  # =============================================================================

  # --- App.tsx ---
  if echo "$TS_ERRORS" | grep -q "App.tsx"; then
    info "App.tsx を強制修正..."
    cat > "$SRC/App.tsx" << 'APPTSX'
import React from 'react'
import { Routes, Route, Navigate } from 'react-router-dom'
import { authStore } from './store/auth'
import Login from './pages/Login'
import Dashboard from './pages/Dashboard'
import InputNew from './pages/InputNew'
import IssueList from './pages/IssueList'
import IssueDetail from './pages/IssueDetail'
import Decisions from './pages/Decisions'
import Labels from './pages/Labels'
import Search from './pages/Search'
import UserManagement from './pages/UserManagement'
import Layout from './components/Layout'
import NotificationToast from './components/NotificationToast'

function PrivateRoute({ children }: { children: React.ReactNode }) {
  return authStore.isLoggedIn() ? <>{children}</> : <Navigate to="/login" replace />
}

export default function App() {
  return (
    <>
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
          <Route path="decisions" element={<Decisions />} />
          <Route path="labels" element={<Labels />} />
          <Route path="search" element={<Search />} />
          <Route path="users" element={<UserManagement />} />
        </Route>
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
      <NotificationToast />
    </>
  )
}
APPTSX
    success "App.tsx 強制上書き完了"
  fi

  # --- IssueDetail.tsx ---
  if echo "$TS_ERRORS" | grep -q "IssueDetail.tsx"; then
    info "IssueDetail.tsx のエラー確認..."
    head -30 "$SRC/pages/IssueDetail.tsx"
    echo ""
    ISSUE_ERRORS=$(echo "$TS_ERRORS" | grep "IssueDetail.tsx" | wc -l)
    info "IssueDetail.tsx エラー件数: $ISSUE_ERRORS"
    if [[ "$ISSUE_ERRORS" -gt 5 ]]; then
      info "エラー多数 → IssueDetail.tsx を標準版で書き直し..."
      cat > "$SRC/pages/IssueDetail.tsx" << 'ISSUETSX'
import React, { useEffect, useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { api } from '../api/client'

interface Issue {
  id: number
  title: string
  description: string
  status: string
  priority: string
  assignee_id?: number
  due_date?: string
  labels?: string[]
  project_id: number
}

interface TraceData {
  issue?: { id: number; title: string }
  action?: { id: number; action_type: string; decision_reason?: string }
  item?: { id: number; text: string; intent: string }
  input?: { id: number; raw_text: string; source: string; created_at: string }
}

const STATUS_OPTIONS = ['open', 'in_progress', 'review', 'done', 'hold']
const PRIORITY_OPTIONS = ['low', 'medium', 'high', 'critical']

export default function IssueDetail() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const [issue, setIssue] = useState<Issue | null>(null)
  const [trace, setTrace] = useState<TraceData | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [activeTab, setActiveTab] = useState<'detail' | 'trace'>('detail')
  const [saving, setSaving] = useState(false)
  const [editStatus, setEditStatus] = useState('')
  const [editPriority, setEditPriority] = useState('')

  useEffect(() => {
    if (!id) return
    Promise.all([
      api.get(`/issues/${id}`),
      api.get(`/trace/${id}`).catch(() => null)
    ]).then(([issueRes, traceRes]) => {
      setIssue(issueRes.data)
      setEditStatus(issueRes.data.status)
      setEditPriority(issueRes.data.priority)
      if (traceRes) setTrace(traceRes.data)
    }).catch(e => {
      setError(e?.response?.data?.detail || '課題の取得に失敗しました')
    }).finally(() => setLoading(false))
  }, [id])

  const handleSave = async () => {
    if (!issue) return
    setSaving(true)
    try {
      const res = await api.patch(`/issues/${issue.id}`, {
        status: editStatus,
        priority: editPriority
      })
      setIssue(res.data)
      setEditStatus(res.data.status)
      setEditPriority(res.data.priority)
    } catch {
      alert('保存に失敗しました')
    } finally {
      setSaving(false)
    }
  }

  if (loading) return <div style={{ padding: 32, color: '#94a3b8' }}>読み込み中...</div>
  if (error)   return <div style={{ padding: 32, color: '#f87171' }}>{error}</div>
  if (!issue)  return <div style={{ padding: 32, color: '#94a3b8' }}>課題が見つかりません</div>

  const card: React.CSSProperties = {
    background: '#1e293b', borderRadius: 8, padding: '16px 20px', marginBottom: 12
  }
  const label: React.CSSProperties = {
    fontSize: 11, color: '#64748b', textTransform: 'uppercase', marginBottom: 4
  }
  const val: React.CSSProperties = { color: '#e2e8f0', fontSize: 14 }
  const selectStyle: React.CSSProperties = {
    background: '#0f172a', color: '#e2e8f0', border: '1px solid #334155',
    borderRadius: 4, padding: '4px 8px', fontSize: 13
  }

  return (
    <div style={{ padding: 24, maxWidth: 900, margin: '0 auto' }}>
      {/* ヘッダ */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 20 }}>
        <button
          onClick={() => navigate(-1)}
          style={{ background: 'none', border: 'none', color: '#60a5fa', cursor: 'pointer', fontSize: 13 }}
        >
          ← 戻る
        </button>
        <h1 style={{ color: '#f1f5f9', fontSize: 20, fontWeight: 700, margin: 0 }}>
          #{issue.id} {issue.title}
        </h1>
      </div>

      {/* タブ */}
      <div style={{ display: 'flex', gap: 4, marginBottom: 20, borderBottom: '1px solid #1e293b' }}>
        {(['detail', 'trace'] as const).map(tab => (
          <button
            key={tab}
            onClick={() => setActiveTab(tab)}
            style={{
              padding: '8px 16px', border: 'none', cursor: 'pointer', fontSize: 13,
              borderBottom: activeTab === tab ? '2px solid #60a5fa' : '2px solid transparent',
              background: 'none',
              color: activeTab === tab ? '#60a5fa' : '#94a3b8'
            }}
          >
            {tab === 'detail' ? '詳細' : 'トレーサビリティ'}
          </button>
        ))}
      </div>

      {activeTab === 'detail' && (
        <div>
          {/* ステータス・優先度 */}
          <div style={{ ...card, display: 'flex', gap: 24 }}>
            <div>
              <div style={label}>ステータス</div>
              <select
                value={editStatus}
                onChange={e => setEditStatus(e.target.value)}
                style={selectStyle}
              >
                {STATUS_OPTIONS.map(s => <option key={s} value={s}>{s}</option>)}
              </select>
            </div>
            <div>
              <div style={label}>優先度</div>
              <select
                value={editPriority}
                onChange={e => setEditPriority(e.target.value)}
                style={selectStyle}
              >
                {PRIORITY_OPTIONS.map(p => <option key={p} value={p}>{p}</option>)}
              </select>
            </div>
            <div style={{ marginLeft: 'auto', alignSelf: 'flex-end' }}>
              <button
                onClick={handleSave}
                disabled={saving}
                style={{
                  background: '#2563eb', color: '#fff', border: 'none',
                  borderRadius: 6, padding: '6px 16px', cursor: 'pointer', fontSize: 13
                }}
              >
                {saving ? '保存中...' : '保存'}
              </button>
            </div>
          </div>

          {/* 説明 */}
          <div style={card}>
            <div style={label}>説明</div>
            <div style={{ ...val, whiteSpace: 'pre-wrap' }}>{issue.description || '（説明なし）'}</div>
          </div>

          {/* ラベル */}
          {issue.labels && issue.labels.length > 0 && (
            <div style={card}>
              <div style={label}>ラベル</div>
              <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                {issue.labels.map(l => (
                  <span key={l} style={{
                    background: '#334155', color: '#94a3b8', borderRadius: 4,
                    padding: '2px 8px', fontSize: 12
                  }}>{l}</span>
                ))}
              </div>
            </div>
          )}
        </div>
      )}

      {activeTab === 'trace' && (
        <div>
          {trace ? (
            <div>
              {/* 課題 */}
              <div style={{ ...card, borderLeft: '3px solid #60a5fa' }}>
                <div style={label}>📋 ISSUE（この課題）</div>
                <div style={val}>#{trace.issue?.id} {trace.issue?.title || issue.title}</div>
              </div>
              {/* アクション */}
              {trace.action && (
                <div style={{ ...card, borderLeft: '3px solid #a78bfa', marginLeft: 24 }}>
                  <div style={label}>⚡ ACTION（課題化の判断）</div>
                  <div style={val}>種別: {trace.action.action_type}</div>
                  {trace.action.decision_reason && (
                    <div style={{ ...val, color: '#94a3b8', fontSize: 12, marginTop: 4 }}>
                      理由: {trace.action.decision_reason}
                    </div>
                  )}
                </div>
              )}
              {/* アイテム */}
              {trace.item && (
                <div style={{ ...card, borderLeft: '3px solid #34d399', marginLeft: 48 }}>
                  <div style={label}>🔹 ITEM（分解された意味単位）</div>
                  <div style={val}>"{trace.item.text}"</div>
                  <div style={{ ...val, color: '#94a3b8', fontSize: 12, marginTop: 4 }}>
                    intent: {trace.item.intent}
                  </div>
                </div>
              )}
              {/* インプット */}
              {trace.input && (
                <div style={{ ...card, borderLeft: '3px solid #fbbf24', marginLeft: 72 }}>
                  <div style={label}>📥 INPUT（元の要望原文）</div>
                  <div style={{ ...val, fontSize: 12, whiteSpace: 'pre-wrap', maxHeight: 120, overflow: 'auto' }}>
                    {trace.input.raw_text}
                  </div>
                  <div style={{ ...val, color: '#64748b', fontSize: 11, marginTop: 6 }}>
                    ソース: {trace.input.source} ／ {trace.input.created_at?.slice(0, 16)}
                  </div>
                </div>
              )}
            </div>
          ) : (
            <div style={{ ...card, color: '#64748b' }}>
              トレース情報がありません（このIssueはACTIONから生成されていないか、データが未接続です）
            </div>
          )}
        </div>
      )}
    </div>
  )
}
ISSUETSX
      success "IssueDetail.tsx 書き直し完了"
    fi
  fi

  # --- Layout.tsx ---
  if echo "$TS_ERRORS" | grep -q "Layout.tsx"; then
    info "Layout.tsx のエラー修正..."
    # まず現状を確認
    python3 << 'PYEOF'
import re
path = "/home/karkyon/projects/decision-os/frontend/src/components/Layout.tsx"
try:
    with open(path) as f:
        content = f.read()
    print("=== 現在のLayout.tsx先頭50行 ===")
    lines = content.split('\n')
    for i, l in enumerate(lines[:50], 1):
        print(f"  {i:3d}: {l}")
except Exception as e:
    print(f"読み取りエラー: {e}")
PYEOF
  fi

  # --- その他のファイル ---
  OTHER_ERRORS=$(echo "$TS_ERRORS" | grep -v "App.tsx\|IssueDetail.tsx\|Layout.tsx" | grep -oP 'src/[^(]+' | sort -u)
  if [[ -n "$OTHER_ERRORS" ]]; then
    info "その他エラーファイル:"
    echo "$OTHER_ERRORS"
    echo "$TS_ERRORS" | grep -v "App.tsx\|IssueDetail.tsx\|Layout.tsx"
  fi

  # =============================================================================
  section "1-B. 修正後 再ビルド"
  # =============================================================================
  info "npm run build 再実行..."
  BUILD_OUT2=$(npm run build 2>&1 || true)
  TS_ERRORS2=$(echo "$BUILD_OUT2" | grep "error TS" || true)

  if [[ -z "$TS_ERRORS2" ]]; then
    success "✅ TSビルドエラー解消！ビルド成功"
    echo "$BUILD_OUT2" | tail -5
  else
    error "残存エラー:"
    echo "$TS_ERRORS2"
    info "→ 残存エラーは次のスクリプトで個別対応します"
  fi
fi

# =============================================================================
section "2. 課題一覧バグ診断（STEP3保存後にIssueが表示されない）"
# =============================================================================

info "バックエンドの起動確認..."
HEALTH=$(curl -s http://localhost:8089/health 2>/dev/null || echo "DOWN")
echo "  バックエンド: $HEALTH"

if echo "$HEALTH" | grep -q "ok\|healthy\|status"; then
  info "ログイン → token取得..."
  LOGIN_RES=$(curl -s -X POST http://localhost:8089/api/v1/auth/login \
    -H "Content-Type: application/json" \
    -d '{"email":"demo@example.com","password":"demo1234"}' 2>/dev/null || echo "{}")

  TOKEN=$(echo "$LOGIN_RES" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('access_token',''))" 2>/dev/null || echo "")

  if [[ -z "$TOKEN" ]]; then
    warn "トークン取得失敗。ログインレスポンス:"
    echo "$LOGIN_RES" | head -200
  else
    success "トークン取得成功"

    # プロジェクト一覧
    info "プロジェクト一覧..."
    PROJECTS=$(curl -s http://localhost:8089/api/v1/projects \
      -H "Authorization: Bearer $TOKEN" 2>/dev/null || echo "[]")
    echo "  プロジェクト: $PROJECTS" | head -c 300
    echo ""

    PROJECT_ID=$(echo "$PROJECTS" | python3 -c "
import sys, json
d = json.load(sys.stdin)
if isinstance(d, list) and d:
    print(d[0]['id'])
elif isinstance(d, dict) and d.get('items'):
    print(d['items'][0]['id'])
else:
    print('')
" 2>/dev/null || echo "")

    if [[ -n "$PROJECT_ID" ]]; then
      info "プロジェクトID: $PROJECT_ID"

      # Issue一覧
      info "Issue一覧確認..."
      ISSUES=$(curl -s "http://localhost:8089/api/v1/issues?project_id=$PROJECT_ID" \
        -H "Authorization: Bearer $TOKEN" 2>/dev/null || echo "[]")
      ISSUE_COUNT=$(echo "$ISSUES" | python3 -c "
import sys, json
d = json.load(sys.stdin)
if isinstance(d, list): print(len(d))
elif isinstance(d, dict): print(len(d.get('items', d.get('issues', []))))
else: print(0)
" 2>/dev/null || echo "?")
      info "  Issue件数: $ISSUE_COUNT"

      # Action一覧（最新5件）
      info "Action一覧確認..."
      ACTIONS=$(curl -s "http://localhost:8089/api/v1/actions?project_id=$PROJECT_ID&limit=5" \
        -H "Authorization: Bearer $TOKEN" 2>/dev/null || echo "[]")
      echo "  Actions (先頭300字): $(echo "$ACTIONS" | head -c 300)"
      echo ""

      # CREATE_ISSUEタイプのActionを探す
      CREATE_ISSUE_ACTIONS=$(echo "$ACTIONS" | python3 -c "
import sys, json
d = json.load(sys.stdin)
items = d if isinstance(d, list) else d.get('items', d.get('actions', []))
ci = [a for a in items if a.get('action_type') == 'CREATE_ISSUE']
print(f'CREATE_ISSUE actions: {len(ci)}件')
for a in ci[:3]:
    print(f'  id={a[\"id\"]} item_id={a.get(\"item_id\")} issue_id={a.get(\"issue_id\")}')
" 2>/dev/null || echo "解析失敗")
      info "$CREATE_ISSUE_ACTIONS"

      # /actions/{id}/convert エンドポイントの存在確認
      info "/actions エンドポイント一覧確認..."
      curl -s http://localhost:8089/openapi.json 2>/dev/null | python3 -c "
import sys, json
try:
    spec = json.load(sys.stdin)
    paths = spec.get('paths', {})
    action_paths = [p for p in paths if 'action' in p.lower()]
    for p in sorted(action_paths):
        methods = list(paths[p].keys())
        print(f'  {p}: {methods}')
except:
    print('openapi.json 解析失敗')
"
    else
      warn "プロジェクトが0件。デモデータの投入が必要です"
      info "プロジェクト作成コマンド:"
      echo "  curl -s -X POST http://localhost:8089/api/v1/projects \\"
      echo "    -H 'Authorization: Bearer \$TOKEN' \\"
      echo "    -H 'Content-Type: application/json' \\"
      echo "    -d '{\"name\":\"デモプロジェクト\",\"description\":\"Phase1動作確認用\"}'"
    fi
  fi
else
  warn "バックエンドが起動していません"
  info "起動コマンド:"
  echo "  cd ~/projects/decision-os/backend && source .venv/bin/activate"
  echo "  nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload &"
fi

# =============================================================================
section "3. フロントエンド IssueList.tsx の project_id フィルタ確認"
# =============================================================================
ISSUELIST="$SRC/pages/IssueList.tsx"
if [[ -f "$ISSUELIST" ]]; then
  info "IssueList.tsx の API呼び出し部分:"
  grep -n "api\.\|fetch\|axios\|useEffect\|project_id\|/issues" "$ISSUELIST" | head -20
else
  warn "IssueList.tsx が見つかりません"
fi

# =============================================================================
section "4. 診断サマリー"
# =============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  診断結果を貼り付けてください。"
echo "  特に確認ポイント："
echo "  ① TSビルドエラーが解消されているか（1-B の結果）"
echo "  ② Issue件数が0か（#2 バグかデータなしか）"
echo "  ③ /actions/{id}/convert エンドポイントが存在するか"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
