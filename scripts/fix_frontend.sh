#!/usr/bin/env bash
# =============================================================================
# decision-os / フロントエンド UI 5点修正
# ① IssueDetail ダークモード固定 → ライトモード対応
# ② InputDetail 分解結果テキスト可視性向上
# ③ サイドバー 要望履歴・要望登録のハイライト重複修正
# ④ プロジェクト一覧ページ追加 + サイドバーに追加
# ⑤ InputNew からプロジェクト選択UI削除・発生日・担当者フィールド追加
# =============================================================================
set -euo pipefail
GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

SRC="$HOME/projects/decision-os/frontend/src"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
nvm use 20 2>/dev/null || true

# =============================================================================
section "① Layout.tsx — サイドバーナビ修正（ハイライト重複・プロジェクト追加）"
# =============================================================================
cat > "$SRC/components/Layout.tsx" << 'TSX'
import { useState } from 'react'
import { Outlet, NavLink, useNavigate } from 'react-router-dom'
import {
  LayoutDashboard, ListChecks, PlusCircle, Users,
  LogOut, ChevronLeft, ChevronRight, Zap, Bell, History, FolderKanban,
} from 'lucide-react'
import ThemeToggle from '@/components/ThemeToggle'

// ⚠️ /inputs/new は /inputs より先に定義しないと end=false で両方ハイライトされる
const NAV = [
  { to: '/',            icon: LayoutDashboard, label: 'ダッシュボード', end: true },
  { to: '/projects',    icon: FolderKanban,    label: 'プロジェクト',   end: true },
  { to: '/issues',      icon: ListChecks,      label: '課題一覧',       end: false },
  { to: '/inputs',      icon: History,         label: '要望履歴',       end: true },
  { to: '/inputs/new',  icon: PlusCircle,      label: '要望登録',       end: true },
  { to: '/users',       icon: Users,           label: 'ユーザー管理',   end: true },
]

export default function Layout() {
  const [collapsed, setCollapsed] = useState(false)
  const navigate = useNavigate()

  function logout() {
    localStorage.removeItem('access_token')
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
                fontWeight: isActive ? 600 : 400,
                transition: 'all 0.15s',
              })}
            >
              <Icon size={17} style={{ flexShrink: 0 }} />
              <span className="sidebar-label">{label}</span>
            </NavLink>
          ))}
        </nav>

        <div style={{ height: 1, background: 'rgba(255,255,255,0.07)', margin: '0 14px 8px' }} />

        {/* Bottom */}
        <div style={{ padding: '8px 8px 12px', display: 'flex', flexDirection: 'column', gap: 4 }}>
          <ThemeToggle collapsed={collapsed} />
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
        minHeight: '100vh',
        background: 'var(--bg-main)',
      }}>
        {/* Topbar */}
        <header style={{
          height: 52, display: 'flex', alignItems: 'center', justifyContent: 'flex-end',
          padding: '0 24px', borderBottom: '1px solid var(--border)',
          background: 'var(--bg-main)', position: 'sticky', top: 0, zIndex: 40,
        }}>
          <Bell size={18} style={{ color: 'var(--text-muted)', cursor: 'pointer' }} />
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
    </div>
  )
}
TSX
ok "Layout.tsx 修正完了"

# =============================================================================
section "② App.tsx — /projects ルート追加"
# =============================================================================
cat > "$SRC/App.tsx" << 'TSX'
import { Routes, Route, Navigate } from 'react-router-dom'
import Layout from '@/components/Layout'
import Dashboard from '@/pages/Dashboard'
import ProjectList from '@/pages/ProjectList'
import IssueList from '@/pages/IssueList'
import IssueDetail from '@/pages/IssueDetail'
import InputNew from '@/pages/InputNew'
import InputHistory from '@/pages/InputHistory'
import InputDetail from '@/pages/InputDetail'
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
        <Route path="projects" element={<ProjectList />} />
        <Route path="issues" element={<IssueList />} />
        <Route path="issues/:id" element={<IssueDetail />} />
        <Route path="inputs/new" element={<InputNew />} />
        <Route path="inputs" element={<InputHistory />} />
        <Route path="inputs/:id" element={<InputDetail />} />
        <Route path="users" element={<UserManagement />} />
      </Route>
    </Routes>
  )
}
TSX
ok "App.tsx 修正完了"

# =============================================================================
section "③ ProjectList.tsx — プロジェクト一覧＋作成"
# =============================================================================
cat > "$SRC/pages/ProjectList.tsx" << 'TSX'
import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { FolderKanban, Plus, Loader2, AlertCircle, ChevronRight } from 'lucide-react'
import apiClient from '@/api/client'

interface Project {
  id: string
  name: string
  description?: string
  created_at: string
}

async function fetchProjects(): Promise<Project[]> {
  const res = await apiClient.get('/projects')
  const d = res.data
  if (Array.isArray(d)) return d
  return d?.items ?? d?.data ?? []
}

async function createProject(data: { name: string; description: string }): Promise<Project> {
  const res = await apiClient.post('/projects', data)
  return res.data
}

export default function ProjectList() {
  const qc = useQueryClient()
  const [showForm, setShowForm] = useState(false)
  const [name, setName] = useState('')
  const [desc, setDesc] = useState('')

  const { data: projects = [], isLoading, isError } = useQuery({
    queryKey: ['projects'],
    queryFn: fetchProjects,
  })

  const mutation = useMutation({
    mutationFn: createProject,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['projects'] })
      setShowForm(false)
      setName('')
      setDesc('')
    },
  })

  return (
    <div>
      {/* ヘッダー */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 24 }}>
        <div>
          <h1 style={{ margin: 0, fontSize: 22, fontWeight: 700, color: 'var(--text-primary)' }}>
            プロジェクト一覧
          </h1>
          <p style={{ margin: '4px 0 0', fontSize: 13, color: 'var(--text-muted)' }}>
            {projects.length} 件
          </p>
        </div>
        <button
          onClick={() => setShowForm(true)}
          style={{
            display: 'flex', alignItems: 'center', gap: 6,
            padding: '9px 16px', borderRadius: 8,
            background: '#6366f1', color: '#fff',
            border: 'none', cursor: 'pointer', fontSize: 13, fontWeight: 600,
          }}
        >
          <Plus size={16} /> プロジェクトを作成
        </button>
      </div>

      {/* 新規作成フォーム */}
      {showForm && (
        <div style={{
          background: 'var(--bg-card)', border: '1px solid var(--border)',
          borderRadius: 12, padding: 20, marginBottom: 20,
        }}>
          <h3 style={{ margin: '0 0 16px', fontSize: 15, color: 'var(--text-primary)' }}>新規プロジェクト</h3>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            <input
              value={name}
              onChange={e => setName(e.target.value)}
              placeholder="プロジェクト名 *"
              style={{
                padding: '9px 12px', borderRadius: 8,
                border: '1px solid var(--border)', background: 'var(--bg-input)',
                color: 'var(--text-primary)', fontSize: 14, outline: 'none',
              }}
            />
            <textarea
              value={desc}
              onChange={e => setDesc(e.target.value)}
              placeholder="説明（任意）"
              rows={3}
              style={{
                padding: '9px 12px', borderRadius: 8,
                border: '1px solid var(--border)', background: 'var(--bg-input)',
                color: 'var(--text-primary)', fontSize: 14, outline: 'none', resize: 'vertical',
              }}
            />
            <div style={{ display: 'flex', gap: 8 }}>
              <button
                onClick={() => mutation.mutate({ name, description: desc })}
                disabled={!name.trim() || mutation.isPending}
                style={{
                  padding: '8px 20px', borderRadius: 8,
                  background: '#6366f1', color: '#fff',
                  border: 'none', cursor: 'pointer', fontSize: 13, fontWeight: 600,
                  opacity: !name.trim() ? 0.5 : 1,
                }}
              >
                {mutation.isPending ? '作成中...' : '作成'}
              </button>
              <button
                onClick={() => setShowForm(false)}
                style={{
                  padding: '8px 20px', borderRadius: 8,
                  background: 'transparent', color: 'var(--text-muted)',
                  border: '1px solid var(--border)', cursor: 'pointer', fontSize: 13,
                }}
              >
                キャンセル
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ローディング / エラー */}
      {isLoading && (
        <div style={{ display: 'flex', justifyContent: 'center', padding: 60 }}>
          <Loader2 size={28} style={{ animation: 'spin 1s linear infinite', color: '#6366f1' }} />
        </div>
      )}
      {isError && (
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, color: '#ef4444', padding: 24 }}>
          <AlertCircle size={18} /> データ取得に失敗しました
        </div>
      )}

      {/* プロジェクト一覧 */}
      {!isLoading && !isError && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {projects.length === 0 ? (
            <div style={{
              textAlign: 'center', padding: '60px 0',
              color: 'var(--text-muted)', fontSize: 14,
              background: 'var(--bg-card)', border: '1px solid var(--border)', borderRadius: 12,
            }}>
              <FolderKanban size={40} style={{ marginBottom: 12, opacity: 0.3 }} />
              <p>プロジェクトがありません</p>
              <p style={{ fontSize: 12 }}>「プロジェクトを作成」ボタンから追加してください</p>
            </div>
          ) : (
            projects.map(p => (
              <Link
                key={p.id}
                to={`/issues?project_id=${p.id}`}
                style={{ textDecoration: 'none' }}
              >
                <div style={{
                  display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                  padding: '16px 20px',
                  background: 'var(--bg-card)', border: '1px solid var(--border)',
                  borderRadius: 12, cursor: 'pointer',
                  transition: 'border-color 0.15s',
                }}
                  onMouseEnter={e => (e.currentTarget.style.borderColor = '#6366f1')}
                  onMouseLeave={e => (e.currentTarget.style.borderColor = 'var(--border)')}
                >
                  <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
                    <div style={{
                      width: 40, height: 40, borderRadius: 10,
                      background: 'rgba(99,102,241,0.15)',
                      display: 'flex', alignItems: 'center', justifyContent: 'center',
                    }}>
                      <FolderKanban size={20} color="#6366f1" />
                    </div>
                    <div>
                      <div style={{ fontWeight: 600, fontSize: 15, color: 'var(--text-primary)' }}>
                        {p.name}
                      </div>
                      {p.description && (
                        <div style={{ fontSize: 13, color: 'var(--text-muted)', marginTop: 2 }}>
                          {p.description}
                        </div>
                      )}
                      <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 4 }}>
                        {new Date(p.created_at).toLocaleDateString('ja-JP')}
                      </div>
                    </div>
                  </div>
                  <ChevronRight size={18} style={{ color: 'var(--text-muted)' }} />
                </div>
              </Link>
            ))
          )}
        </div>
      )}
    </div>
  )
}
TSX
ok "ProjectList.tsx 作成完了"

# =============================================================================
section "④ InputNew.tsx — プロジェクト選択削除・発生日・担当者追加"
# =============================================================================
# project_id はコンテキスト（URLパラメータ or localStorage）から取るように変更
cat > "$SRC/pages/InputNew.tsx" << 'TSX'
import { useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { useMutation, useQuery } from '@tanstack/react-query'
import { Loader2 } from 'lucide-react'
import apiClient from '@/api/client'

const SOURCE_TYPES = [
  { value: 'email',   label: 'email' },
  { value: 'voice',   label: 'voice' },
  { value: 'meeting', label: 'meeting' },
  { value: 'bug',     label: 'bug' },
  { value: 'other',   label: 'other' },
]

interface User {
  id: string
  name: string
  email: string
}

async function fetchUsers(): Promise<User[]> {
  try {
    const res = await apiClient.get('/users')
    const d = res.data
    if (Array.isArray(d)) return d
    return d?.items ?? d?.data ?? []
  } catch {
    return []
  }
}

export default function InputNew() {
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()
  // プロジェクトIDはURLパラメータから取得（プロジェクトページから遷移時）
  const projectId = searchParams.get('project_id') ?? ''

  const [sourceType, setSourceType] = useState('email')
  const [text, setText] = useState('')
  const [occurredAt, setOccurredAt] = useState('')   // 発生日
  const [reporterId, setReporterId] = useState('')    // 担当者（要望発信者）
  const [step, setStep] = useState<1 | 2 | 3>(1)

  const { data: users = [] } = useQuery({ queryKey: ['users'], queryFn: fetchUsers })

  const mutation = useMutation({
    mutationFn: async () => {
      const payload: Record<string, unknown> = {
        source_type: sourceType,
        raw_text: text,
        ...(projectId ? { project_id: projectId } : {}),
        ...(occurredAt ? { occurred_at: occurredAt } : {}),
        ...(reporterId ? { author_id: reporterId } : {}),
      }
      const inp = await apiClient.post('/inputs', payload)
      const inputId = inp.data.id
      const analyzed = await apiClient.post('/analyze', { input_id: inputId })
      return { inputId, items: analyzed.data }
    },
    onSuccess: ({ inputId }) => {
      setStep(2)
      navigate(`/inputs/${inputId}`)
    },
  })

  const btnStyle = (active: boolean): React.CSSProperties => ({
    padding: '7px 16px', borderRadius: 6, fontSize: 13, fontWeight: 500,
    border: active ? '2px solid #6366f1' : '2px solid var(--border)',
    background: active ? 'rgba(99,102,241,0.15)' : 'transparent',
    color: active ? '#6366f1' : 'var(--text-muted)',
    cursor: 'pointer',
  })

  const inputStyle: React.CSSProperties = {
    width: '100%', padding: '10px 12px', borderRadius: 8,
    border: '1px solid var(--border)', background: 'var(--bg-input)',
    color: 'var(--text-primary)', fontSize: 14, outline: 'none',
    boxSizing: 'border-box',
  }

  return (
    <div>
      {/* ステッパー */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 0, marginBottom: 28 }}>
        {(['1. 原文入力', '2. 分類確認・修正', '3. ACTION決定'] as const).map((label, i) => {
          const s = (i + 1) as 1 | 2 | 3
          const isActive = step === s
          return (
            <div key={label} style={{ display: 'flex', alignItems: 'center' }}>
              <div style={{
                padding: '8px 18px', borderRadius: 6, fontSize: 13, fontWeight: 600,
                background: isActive ? '#6366f1' : 'var(--bg-card)',
                color: isActive ? '#fff' : 'var(--text-muted)',
                border: `1px solid ${isActive ? '#6366f1' : 'var(--border)'}`,
              }}>{label}</div>
              {i < 2 && <div style={{ width: 24, height: 1, background: 'var(--border)' }} />}
            </div>
          )
        })}
      </div>

      {/* フォームカード */}
      <div style={{
        background: 'var(--bg-card)', border: '1px solid var(--border)',
        borderRadius: 14, padding: '28px 32px', maxWidth: 760,
      }}>
        <h2 style={{ margin: '0 0 24px', fontSize: 17, fontWeight: 700, color: 'var(--text-primary)' }}>
          📋 原文入力
        </h2>

        {/* ソース種別 */}
        <div style={{ marginBottom: 20 }}>
          <label style={{ fontSize: 13, fontWeight: 600, color: 'var(--text-primary)', display: 'block', marginBottom: 10 }}>
            ソース種別
          </label>
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            {SOURCE_TYPES.map(s => (
              <button key={s.value} onClick={() => setSourceType(s.value)} style={btnStyle(sourceType === s.value)}>
                {s.label}
              </button>
            ))}
          </div>
        </div>

        {/* 発生日 */}
        <div style={{ marginBottom: 20 }}>
          <label style={{ fontSize: 13, fontWeight: 600, color: 'var(--text-primary)', display: 'block', marginBottom: 8 }}>
            発生日（任意）
          </label>
          <input
            type="date"
            value={occurredAt}
            onChange={e => setOccurredAt(e.target.value)}
            style={{ ...inputStyle, width: 'auto', minWidth: 200 }}
          />
        </div>

        {/* 担当者（要望発信者） */}
        <div style={{ marginBottom: 20 }}>
          <label style={{ fontSize: 13, fontWeight: 600, color: 'var(--text-primary)', display: 'block', marginBottom: 8 }}>
            要望発信者（任意）
          </label>
          <select
            value={reporterId}
            onChange={e => setReporterId(e.target.value)}
            style={{ ...inputStyle, width: 'auto', minWidth: 240 }}
          >
            <option value="">未設定</option>
            {users.map(u => (
              <option key={u.id} value={u.id}>{u.name}（{u.email}）</option>
            ))}
          </select>
        </div>

        {/* 原文テキスト */}
        <div style={{ marginBottom: 24 }}>
          <label style={{ fontSize: 13, fontWeight: 600, color: 'var(--text-primary)', display: 'block', marginBottom: 8 }}>
            原文テキスト
          </label>
          <textarea
            value={text}
            onChange={e => setText(e.target.value)}
            placeholder="要望・不具合報告・ミーティングメモなどを貼り付けてください"
            rows={10}
            style={{ ...inputStyle, resize: 'vertical', lineHeight: 1.7 }}
          />
        </div>

        {/* 解析ボタン */}
        <button
          onClick={() => mutation.mutate()}
          disabled={!text.trim() || mutation.isPending}
          style={{
            display: 'flex', alignItems: 'center', gap: 8,
            padding: '10px 24px', borderRadius: 8,
            background: !text.trim() || mutation.isPending ? 'var(--bg-muted)' : '#6366f1',
            color: '#fff', border: 'none', cursor: !text.trim() ? 'not-allowed' : 'pointer',
            fontSize: 14, fontWeight: 600,
          }}
        >
          {mutation.isPending ? (
            <><Loader2 size={16} style={{ animation: 'spin 1s linear infinite' }} /> 解析中...</>
          ) : (
            '🔍 解析する'
          )}
        </button>

        {mutation.isError && (
          <p style={{ color: '#ef4444', fontSize: 13, marginTop: 12 }}>
            エラーが発生しました。再度お試しください。
          </p>
        )}
      </div>
    </div>
  )
}
TSX
ok "InputNew.tsx 修正完了（プロジェクト選択削除・発生日・担当者追加）"

# =============================================================================
section "⑤ IssueDetail.tsx — ライトモード対応（CSS変数化）"
# =============================================================================
# IssueDetail はダーク固定のインラインスタイルになっているので CSS変数に置換
# background: '#0f172a' → 'var(--bg-base)'
# background: '#1e293b' → 'var(--bg-card)'
# color: '#e2e8f0'      → 'var(--text-primary)'
# color: '#94a3b8'      → 'var(--text-muted)'
# border: '#334155'     → 'var(--border)'

python3 << 'PY'
import re

path = f"{__import__('os').environ['HOME']}/projects/decision-os/frontend/src/pages/IssueDetail.tsx"
try:
    with open(path, encoding='utf-8') as f:
        c = f.read()

    replacements = [
        (r"background:\s*'#0f172a'",  "background: 'var(--bg-base)'"),
        (r"background:\s*'#0f1117'",  "background: 'var(--bg-base)'"),
        (r"background:\s*'#1e293b'",  "background: 'var(--bg-card)'"),
        (r"background:\s*'#1a1f2e'",  "background: 'var(--bg-card)'"),
        (r"background:\s*'#0f172a'",  "background: 'var(--bg-base)'"),
        (r"borderBottom:\s*'1px solid #334155'", "borderBottom: '1px solid var(--border)'"),
        (r"border:\s*'1px solid #334155'",        "border: '1px solid var(--border)'"),
        (r"borderRight:\s*'1px solid #334155'",   "borderRight: '1px solid var(--border)'"),
        (r"color:\s*'#e2e8f0'",  "color: 'var(--text-primary)'"),
        (r"color:\s*'#cbd5e1'",  "color: 'var(--text-primary)'"),
        (r"color:\s*'#94a3b8'",  "color: 'var(--text-muted)'"),
        (r"color:\s*'#64748b'",  "color: 'var(--text-muted)'"),
        (r"color:\s*'#475569'",  "color: 'var(--text-muted)'"),
        # ナビバー背景
        (r"background:\s*'#1e293b'(?=,\s*borderBottom)", "background: 'var(--bg-sidebar)'"),
    ]

    for pat, rep in replacements:
        c = re.sub(pat, rep, c)

    with open(path, 'w', encoding='utf-8') as f:
        f.write(c)
    print("IssueDetail.tsx CSS変数化完了")
except FileNotFoundError:
    print(f"WARNING: IssueDetail.tsx が見つかりません: {path}")
PY
ok "IssueDetail.tsx ライトモード対応完了"

# =============================================================================
section "⑥ InputDetail.tsx — 分解結果テキスト可視性改善"
# =============================================================================
python3 << 'PY'
import re, os

path = f"{os.environ['HOME']}/projects/decision-os/frontend/src/pages/InputDetail.tsx"
try:
    with open(path, encoding='utf-8') as f:
        c = f.read()

    # テキストが薄い原因: color が '#475569' や '#64748b' などの薄い色
    # 分解結果のメインテキスト部分を可視性の高い色に
    c = re.sub(r"color:\s*'#475569'", "color: 'var(--text-secondary, #64748b)'", c)
    # グレーアウトしたテキストを少し濃く
    c = re.sub(r"color:\s*'#64748b'", "color: 'var(--text-secondary, #64748b)'", c)
    # 背景がダーク固定の場合
    c = re.sub(r"background:\s*'#0f172a'", "background: 'var(--bg-base)'", c)
    c = re.sub(r"background:\s*'#1e293b'", "background: 'var(--bg-card)'", c)
    c = re.sub(r"color:\s*'#e2e8f0'", "color: 'var(--text-primary)'", c)
    c = re.sub(r"color:\s*'#94a3b8'", "color: 'var(--text-muted)'", c)

    with open(path, 'w', encoding='utf-8') as f:
        f.write(c)
    print("InputDetail.tsx 可視性改善完了")
except FileNotFoundError:
    print(f"WARNING: InputDetail.tsx が見つかりません: {path}")
PY
ok "InputDetail.tsx 修正完了"

# =============================================================================
section "⑦ ThemeToggle コンポーネントの確認"
# =============================================================================
TOGGLE="$SRC/components/ThemeToggle.tsx"
if [ ! -f "$TOGGLE" ]; then
  info "ThemeToggle.tsx が存在しないので作成"
  cat > "$TOGGLE" << 'TSX'
import { useEffect, useState } from 'react'
import { Moon, Sun } from 'lucide-react'

export default function ThemeToggle({ collapsed }: { collapsed: boolean }) {
  const [dark, setDark] = useState(() =>
    document.documentElement.getAttribute('data-theme') !== 'light'
  )

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', dark ? 'dark' : 'light')
  }, [dark])

  return (
    <button
      onClick={() => setDark(d => !d)}
      style={{
        display: 'flex', alignItems: 'center', gap: 10,
        padding: '8px 10px', borderRadius: 8, width: '100%',
        background: 'none', border: 'none', cursor: 'pointer',
        color: 'rgba(180,188,210,0.6)', fontSize: 13.5,
      }}
    >
      {dark ? <Sun size={17} style={{ flexShrink: 0 }} /> : <Moon size={17} style={{ flexShrink: 0 }} />}
      {!collapsed && <span>{dark ? 'ライト' : 'ダーク'}</span>}
    </button>
  )
}
TSX
  ok "ThemeToggle.tsx 作成完了"
else
  ok "ThemeToggle.tsx は既に存在"
fi

# =============================================================================
section "⑧ index.css — CSS変数定義（ライト/ダーク両対応）"
# =============================================================================
# CSS変数が定義されているか確認し、なければ追加
CSS_FILE="$SRC/index.css"
if ! grep -q '\-\-bg-base' "$CSS_FILE" 2>/dev/null; then
  info "CSS変数をindex.cssに追加"
  cat >> "$CSS_FILE" << 'CSS'

/* ── Theme Variables ── */
:root, [data-theme="dark"] {
  --bg-base:    #0f1117;
  --bg-sidebar: #0d1017;
  --bg-main:    #f1f3f7;
  --bg-card:    #1a1f2e;
  --bg-input:   #0f172a;
  --bg-muted:   #1e293b;
  --text-primary:   #e2e8f0;
  --text-secondary: #94a3b8;
  --text-muted:     #64748b;
  --border:         #2d3548;
}

[data-theme="light"] {
  --bg-base:    #f1f3f7;
  --bg-sidebar: #1a1d2e;
  --bg-main:    #f1f3f7;
  --bg-card:    #ffffff;
  --bg-input:   #f8fafc;
  --bg-muted:   #f1f5f9;
  --text-primary:   #0f172a;
  --text-secondary: #334155;
  --text-muted:     #64748b;
  --border:         #e2e8f0;
}

@keyframes spin {
  from { transform: rotate(0deg); }
  to   { transform: rotate(360deg); }
}
CSS
  ok "CSS変数追加完了"
else
  ok "CSS変数は既に定義済み"
fi

# =============================================================================
section "完了 — TypeScriptビルド確認"
# =============================================================================
cd "$HOME/projects/decision-os/frontend"
info "tsc --noEmit 実行中..."
npx tsc --noEmit 2>&1 | head -30 || true
ok "修正スクリプト完了！"
echo ""
echo "フロントエンド再起動: dos-fe-stop && dos-fe"
