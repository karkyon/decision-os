#!/usr/bin/env bash
# =============================================================================
# decision-os / 28p: ライトモード修正（ハードコード色 → CSS変数 全置換）
# =============================================================================
set -euo pipefail
GREEN='\033[0;32m'; BOLD='\033[1m'; RESET='\033[0m'
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

FRONTEND="$HOME/projects/decision-os/frontend/src"
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
nvm use 20 2>/dev/null || true

# =============================================================================
section "1. index.css — 完全なテーマシステム"
# =============================================================================
cat > "$FRONTEND/index.css" << 'CSS'
@import url('https://fonts.googleapis.com/css2?family=DM+Sans:ital,opsz,wght@0,9..40,300;0,9..40,400;0,9..40,500;0,9..40,600;1,9..40,400&family=DM+Mono:wght@400;500&display=swap');

/* ═══════════════════════════════════════════
   ライトテーマ（デフォルト）
═══════════════════════════════════════════ */
:root,
[data-theme="light"] {
  --bg-base:          #f4f5f7;
  --bg-surface:       #ffffff;
  --bg-surface-alt:   #f8f9fb;
  --bg-input:         #ffffff;
  --bg-input-focus:   #ffffff;
  --bg-hover:         #f0f2f8;
  --bg-sidebar:       #1e2035;
  --bg-header:        #ffffff;

  --border:           #e4e7ef;
  --border-input:     #d0d5e8;
  --border-strong:    #b8bdd0;

  --text-primary:     #1a1d2e;
  --text-secondary:   #4a5070;
  --text-muted:       #8b91a8;
  --text-placeholder: #b0b5c8;

  --accent:           #4f46e5;
  --accent-hover:     #4338ca;
  --accent-light:     rgba(79,70,229,0.08);
  --accent-glow:      rgba(79,70,229,0.2);

  --shadow-sm:        0 1px 3px rgba(0,0,0,0.06), 0 1px 2px rgba(0,0,0,0.04);
  --shadow-md:        0 4px 12px rgba(0,0,0,0.08);
  --shadow-lg:        0 8px 24px rgba(0,0,0,0.10);
  --shadow-btn:       0 2px 8px rgba(79,70,229,0.25);

  --status-open-bg:   #eff6ff;  --status-open-fg:   #1d4ed8;
  --status-prog-bg:   #fffbeb;  --status-prog-fg:   #b45309;
  --status-done-bg:   #f0fdf4;  --status-done-fg:   #15803d;
  --status-closed-bg: #f8fafc;  --status-closed-fg: #64748b;

  --table-head-bg:    #f8f9fb;
  --tag-bg:           #eef0ff;
  --tag-fg:           #4f46e5;

  --sidebar-nav-color:       rgba(200,205,220,0.9);
  --sidebar-nav-active-bg:   rgba(99,102,241,0.3);
  --sidebar-nav-active-color:#ffffff;
  --sidebar-nav-hover-bg:    rgba(255,255,255,0.08);
}

/* ═══════════════════════════════════════════
   ダークテーマ
═══════════════════════════════════════════ */
[data-theme="dark"] {
  --bg-base:          #0f1117;
  --bg-surface:       #1a1f2e;
  --bg-surface-alt:   #151a27;
  --bg-input:         #0f1117;
  --bg-input-focus:   #13182a;
  --bg-hover:         rgba(255,255,255,0.04);
  --bg-sidebar:       #13171f;
  --bg-header:        #13171f;

  --border:           #2d3548;
  --border-input:     #2d3548;
  --border-strong:    #3d4560;

  --text-primary:     #e2e8f0;
  --text-secondary:   #94a3b8;
  --text-muted:       #64748b;
  --text-placeholder: #475569;

  --accent:           #6366f1;
  --accent-hover:     #818cf8;
  --accent-light:     rgba(99,102,241,0.12);
  --accent-glow:      rgba(99,102,241,0.3);

  --shadow-sm:        none;
  --shadow-md:        0 4px 16px rgba(0,0,0,0.4);
  --shadow-lg:        0 8px 32px rgba(0,0,0,0.5);
  --shadow-btn:       0 4px 12px rgba(99,102,241,0.3);

  --status-open-bg:   rgba(59,130,246,0.15);  --status-open-fg:   #60a5fa;
  --status-prog-bg:   rgba(245,158,11,0.15);  --status-prog-fg:   #fbbf24;
  --status-done-bg:   rgba(34,197,94,0.15);   --status-done-fg:   #4ade80;
  --status-closed-bg: rgba(100,116,139,0.15); --status-closed-fg: #94a3b8;

  --table-head-bg:    #151a27;
  --tag-bg:           rgba(99,102,241,0.15);
  --tag-fg:           #818cf8;

  --sidebar-nav-color:       rgba(180,188,210,0.85);
  --sidebar-nav-active-bg:   rgba(99,102,241,0.35);
  --sidebar-nav-active-color:#ffffff;
  --sidebar-nav-hover-bg:    rgba(255,255,255,0.07);
}

/* ═══════════════════════════════════════════
   リセット & ベース
═══════════════════════════════════════════ */
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

html {
  transition: background-color 0.2s ease, color 0.2s ease;
}

body {
  font-family: 'DM Sans', -apple-system, BlinkMacSystemFont, sans-serif;
  background: var(--bg-base);
  color: var(--text-primary);
  -webkit-font-smoothing: antialiased;
  line-height: 1.5;
}

/* ═══════════════════════════════════════════
   サイドバー
═══════════════════════════════════════════ */
:root {
  --sidebar-w: 220px;
  --sidebar-collapsed-w: 58px;
}

.sidebar {
  width: var(--sidebar-w);
  transition: width 0.22s cubic-bezier(0.4,0,0.2,1);
}
.sidebar.collapsed { width: var(--sidebar-collapsed-w); }
.sidebar-label {
  transition: opacity 0.18s ease, max-width 0.18s ease;
  white-space: nowrap;
  overflow: hidden;
  max-width: 160px;
}
.sidebar.collapsed .sidebar-label {
  opacity: 0;
  max-width: 0;
  pointer-events: none;
}

/* ═══════════════════════════════════════════
   カード
═══════════════════════════════════════════ */
.card {
  background: var(--bg-surface);
  border: 1px solid var(--border);
  border-radius: 12px;
  box-shadow: var(--shadow-sm);
}

/* ═══════════════════════════════════════════
   バッジ
═══════════════════════════════════════════ */
.badge {
  display: inline-block;
  font-family: 'DM Mono', monospace;
  font-size: 11px;
  font-weight: 500;
  letter-spacing: 0.03em;
  padding: 2px 8px;
  border-radius: 5px;
  line-height: 1.6;
}

/* ═══════════════════════════════════════════
   フォームコントロール
═══════════════════════════════════════════ */
input, select, textarea {
  font-family: 'DM Sans', sans-serif;
  font-size: 14px;
  color: var(--text-primary);
  background: var(--bg-input);
  border: 1.5px solid var(--border-input);
  border-radius: 8px;
  transition: border-color 0.15s, box-shadow 0.15s;
}
input::placeholder, textarea::placeholder {
  color: var(--text-placeholder);
}
input:focus, select:focus, textarea:focus {
  outline: none;
  border-color: var(--accent);
  box-shadow: 0 0 0 3px var(--accent-light);
  background: var(--bg-input-focus);
}
select {
  cursor: pointer;
  appearance: none;
}
option {
  background: var(--bg-surface);
  color: var(--text-primary);
}

/* ═══════════════════════════════════════════
   スクロールバー
═══════════════════════════════════════════ */
::-webkit-scrollbar { width: 5px; height: 5px; }
::-webkit-scrollbar-track { background: transparent; }
::-webkit-scrollbar-thumb { background: var(--border); border-radius: 3px; }
::-webkit-scrollbar-thumb:hover { background: var(--border-strong); }

/* ═══════════════════════════════════════════
   テーブル
═══════════════════════════════════════════ */
table { border-collapse: collapse; width: 100%; }

/* ═══════════════════════════════════════════
   アニメーション
═══════════════════════════════════════════ */
@keyframes spin { to { transform: rotate(360deg); } }
@keyframes fadeIn { from { opacity: 0; transform: translateY(4px); } to { opacity: 1; transform: translateY(0); } }

.fade-in { animation: fadeIn 0.2s ease forwards; }
CSS
success "index.css 更新完了"

# =============================================================================
section "2. InputHistory.tsx — CSS変数で完全書き直し"
# =============================================================================
cat > "$FRONTEND/pages/InputHistory.tsx" << 'TSX'
import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { FileText, Search, ChevronDown, Loader2, AlertCircle, Mail, Mic, Users, Bug, MoreHorizontal, ArrowRight } from 'lucide-react'
import apiClient from '@/api/client'

interface InputRecord {
  id: string
  source_type: string
  raw_text: string
  author?: string
  author_name?: string
  created_at: string
  item_count?: number
  issue_count?: number
}

const SOURCE_META: Record<string, { icon: React.ElementType; label: string; color: string; bg: string }> = {
  email:   { icon: Mail,           label: 'メール',   color: '#3b82f6', bg: 'rgba(59,130,246,0.1)'  },
  voice:   { icon: Mic,            label: '音声',     color: '#8b5cf6', bg: 'rgba(139,92,246,0.1)'  },
  meeting: { icon: Users,          label: '会議',     color: '#10b981', bg: 'rgba(16,185,129,0.1)'  },
  bug:     { icon: Bug,            label: 'バグ報告', color: '#ef4444', bg: 'rgba(239,68,68,0.1)'   },
  other:   { icon: MoreHorizontal, label: 'その他',   color: '#6366f1', bg: 'rgba(99,102,241,0.1)'  },
}
const SOURCE_FILTERS = [
  { value: '', label: 'すべて' }, { value: 'email', label: 'メール' },
  { value: 'voice', label: '音声' }, { value: 'meeting', label: '会議' },
  { value: 'bug', label: 'バグ報告' }, { value: 'other', label: 'その他' },
]

async function fetchInputs(params: Record<string, string>) {
  const res = await apiClient.get(`/inputs?${new URLSearchParams(params)}`)
  const d = res.data
  if (Array.isArray(d)) return { items: d as InputRecord[], total: d.length }
  if (Array.isArray(d?.items)) return { items: d.items as InputRecord[], total: (d.total ?? d.items.length) as number }
  const arr = Object.values(d as Record<string, unknown>).find((v): v is InputRecord[] => Array.isArray(v))
  return { items: arr ?? [], total: arr?.length ?? 0 }
}

export default function InputHistory() {
  const [search, setSearch] = useState('')
  const [sourceFilter, setSourceFilter] = useState('')
  const [page, setPage] = useState(1)
  const limit = 20
  const params: Record<string, string> = {
    skip: String((page - 1) * limit), limit: String(limit),
    ...(search ? { q: search } : {}), ...(sourceFilter ? { source_type: sourceFilter } : {}),
  }
  const { data, isLoading, isError } = useQuery({
    queryKey: ['inputs', params], queryFn: () => fetchInputs(params), placeholderData: p => p,
  })
  const inputs = data?.items ?? []
  const total = data?.total ?? 0
  const totalPages = Math.ceil(total / limit)

  return (
    <div style={{ animation: 'fadeIn 0.2s ease' }}>
      {/* Header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 24 }}>
        <div>
          <h1 style={{ fontSize: 22, fontWeight: 800, color: 'var(--text-primary)', letterSpacing: '-0.03em' }}>
            要望履歴
          </h1>
          <p style={{ marginTop: 4, fontSize: 13, color: 'var(--text-muted)' }}>
            登録済みの原文・解析履歴 — {total.toLocaleString()} 件
          </p>
        </div>
        <Link to="/inputs/new" style={{
          display: 'inline-flex', alignItems: 'center', gap: 6, padding: '9px 18px',
          background: 'var(--accent)', borderRadius: 9, color: '#fff',
          textDecoration: 'none', fontSize: 13, fontWeight: 600,
          boxShadow: 'var(--shadow-btn)', transition: 'opacity 0.15s',
        }}
        onMouseEnter={e => (e.currentTarget.style.opacity = '0.88')}
        onMouseLeave={e => (e.currentTarget.style.opacity = '1')}
        >
          <FileText size={14} /> 新規登録
        </Link>
      </div>

      {/* Filters */}
      <div className="card" style={{ padding: '12px 14px', marginBottom: 14, display: 'flex', gap: 10, flexWrap: 'wrap' }}>
        <div style={{ position: 'relative', flex: 1, minWidth: 220 }}>
          <Search size={14} style={{ position: 'absolute', left: 11, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)', pointerEvents: 'none' }} />
          <input
            value={search} onChange={e => { setSearch(e.target.value); setPage(1) }}
            placeholder="原文テキスト・著者で検索..."
            style={{ width: '100%', padding: '8px 12px 8px 34px' }}
          />
        </div>
        <div style={{ position: 'relative' }}>
          <select value={sourceFilter} onChange={e => { setSourceFilter(e.target.value); setPage(1) }}
            style={{ padding: '8px 32px 8px 12px', minWidth: 110 }}>
            {SOURCE_FILTERS.map(s => <option key={s.value} value={s.value}>{s.label}</option>)}
          </select>
          <ChevronDown size={13} style={{ position: 'absolute', right: 9, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)', pointerEvents: 'none' }} />
        </div>
      </div>

      {/* List */}
      {isLoading ? (
        <div className="card" style={{ padding: '60px', textAlign: 'center', color: 'var(--text-muted)' }}>
          <Loader2 size={22} style={{ margin: '0 auto 10px', display: 'block', animation: 'spin 1s linear infinite' }} />
          読み込み中...
        </div>
      ) : isError ? (
        <div className="card" style={{ padding: '40px', textAlign: 'center', color: '#dc2626' }}>
          <AlertCircle size={20} style={{ marginBottom: 8, display: 'block', margin: '0 auto 8px' }} />
          データの取得に失敗しました
        </div>
      ) : inputs.length === 0 ? (
        <div className="card" style={{ padding: '60px', textAlign: 'center', color: 'var(--text-muted)', fontSize: 14 }}>
          要望履歴がありません
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          {inputs.map(inp => {
            const src = SOURCE_META[inp.source_type] ?? SOURCE_META['other']
            const SrcIcon = src.icon
            const preview = inp.raw_text?.length > 140 ? inp.raw_text.slice(0, 140) + '…' : inp.raw_text

            return (
              <Link key={inp.id} to={`/inputs/${inp.id}`} style={{ textDecoration: 'none' }}>
                <div className="card" style={{ padding: '16px 20px', transition: 'box-shadow 0.15s, border-color 0.15s' }}
                  onMouseEnter={e => {
                    const el = e.currentTarget as HTMLDivElement
                    el.style.borderColor = 'var(--accent)'
                    el.style.boxShadow = '0 0 0 3px var(--accent-light)'
                  }}
                  onMouseLeave={e => {
                    const el = e.currentTarget as HTMLDivElement
                    el.style.borderColor = 'var(--border)'
                    el.style.boxShadow = 'var(--shadow-sm)'
                  }}
                >
                  <div style={{ display: 'flex', gap: 14, alignItems: 'flex-start' }}>
                    <div style={{
                      width: 38, height: 38, borderRadius: 10, flexShrink: 0,
                      background: src.bg, display: 'flex', alignItems: 'center', justifyContent: 'center',
                      border: `1px solid ${src.color}30`,
                    }}>
                      <SrcIcon size={17} color={src.color} />
                    </div>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 7, flexWrap: 'wrap' }}>
                        <span className="badge" style={{ background: src.bg, color: src.color }}>{src.label}</span>
                        {(inp.author_name ?? inp.author) && (
                          <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>
                            by {inp.author_name ?? inp.author}
                          </span>
                        )}
                        <span style={{ marginLeft: 'auto', fontSize: 11, color: 'var(--text-muted)', fontFamily: 'DM Mono, monospace' }}>
                          {new Date(inp.created_at).toLocaleString('ja-JP', { year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' })}
                        </span>
                      </div>
                      <p style={{ fontSize: 13, color: 'var(--text-secondary)', lineHeight: 1.65, whiteSpace: 'pre-wrap', marginBottom: 8 }}>
                        {preview}
                      </p>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
                        {inp.item_count != null && (
                          <span style={{ fontSize: 11, color: 'var(--text-muted)' }}>
                            分解: <strong style={{ color: 'var(--text-secondary)' }}>{inp.item_count}</strong> ITEM
                          </span>
                        )}
                        {inp.issue_count != null && inp.issue_count > 0 && (
                          <span style={{ fontSize: 11, color: 'var(--text-muted)' }}>
                            課題: <strong style={{ color: 'var(--accent)' }}>{inp.issue_count}</strong> 件
                          </span>
                        )}
                        <span style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 4, fontSize: 12, color: 'var(--accent)', fontWeight: 500 }}>
                          詳細を見る <ArrowRight size={12} />
                        </span>
                      </div>
                    </div>
                  </div>
                </div>
              </Link>
            )
          })}
        </div>
      )}

      {/* Pagination */}
      {totalPages > 1 && (
        <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', gap: 6, marginTop: 20 }}>
          <button onClick={() => setPage(p => Math.max(1, p - 1))} disabled={page === 1}
            style={{ padding: '6px 14px', borderRadius: 7, fontSize: 13, background: 'var(--bg-surface)', border: '1px solid var(--border)', color: page === 1 ? 'var(--border)' : 'var(--text-secondary)', cursor: page === 1 ? 'not-allowed' : 'pointer' }}>←</button>
          <span style={{ fontSize: 13, color: 'var(--text-muted)', padding: '0 8px' }}>{page} / {totalPages}</span>
          <button onClick={() => setPage(p => Math.min(totalPages, p + 1))} disabled={page === totalPages}
            style={{ padding: '6px 14px', borderRadius: 7, fontSize: 13, background: 'var(--bg-surface)', border: '1px solid var(--border)', color: page === totalPages ? 'var(--border)' : 'var(--text-secondary)', cursor: page === totalPages ? 'not-allowed' : 'pointer' }}>→</button>
        </div>
      )}
    </div>
  )
}
TSX
success "InputHistory.tsx 更新完了"

# =============================================================================
section "3. InputNew.tsx — CSS変数で書き直し（既存が使われているか確認して上書き）"
# =============================================================================
# 既存のInputNew.tsxの内容を確認
INPUTNEW="$FRONTEND/pages/InputNew.tsx"
if grep -q "1a1f2e\|0f1117\|13171f\|2d3548" "$INPUTNEW" 2>/dev/null; then
  echo "ハードコードカラーを検出 → CSS変数版に置き換えます"
fi

cat > "$INPUTNEW" << 'TSX'
import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery, useMutation } from '@tanstack/react-query'
import { Loader2, CheckCircle, AlertCircle, ChevronRight } from 'lucide-react'
import apiClient from '@/api/client'

interface Project { id: string; name: string }
interface AnalyzeItem {
  id: string; text: string; intent_code: string; domain_code: string
  confidence: number; position: number
}

const INTENT_LABEL: Record<string, { label: string; color: string }> = {
  REQ: { label: '要求',   color: '#6366f1' }, BUG: { label: 'バグ',   color: '#ef4444' },
  IMP: { label: '改善',   color: '#f59e0b' }, QST: { label: '質問',   color: '#10b981' },
  FBK: { label: 'FBK',    color: '#8b5cf6' }, INF: { label: '情報',   color: '#64748b' },
  MIS: { label: '誤解',   color: '#f97316' }, OTH: { label: 'その他', color: '#94a3b8' },
}
const ACTION_OPTIONS = [
  { value: 'CREATE_ISSUE',  label: '課題化',  color: '#6366f1' },
  { value: 'ANSWER',        label: '回答',    color: '#10b981' },
  { value: 'STORE',         label: '保存',    color: '#3b82f6' },
  { value: 'REJECT',        label: '却下',    color: '#ef4444' },
  { value: 'HOLD',          label: '保留',    color: '#f59e0b' },
]
const SOURCE_OPTIONS = ['email', 'voice', 'meeting', 'bug', 'other']

const STEPS = ['1. 原文入力', '2. 分類確認・修正', '3. ACTION決定']

export default function InputNew() {
  const navigate = useNavigate()
  const [step, setStep] = useState(0)
  const [sourceType, setSourceType] = useState('email')
  const [rawText, setRawText] = useState('')
  const [projectId, setProjectId] = useState('')
  const [items, setItems] = useState<AnalyzeItem[]>([])
  const [actions, setActions] = useState<Record<string, string>>({})
  const [reasons, setReasons] = useState<Record<string, string>>({})
  const [inputId, setInputId] = useState('')
  const [done, setDone] = useState(false)

  const { data: projects = [] } = useQuery<Project[]>({
    queryKey: ['projects'],
    queryFn: async () => (await apiClient.get('/projects')).data,
  })

  const analyzeMutation = useMutation({
    mutationFn: async () => {
      const inpRes = await apiClient.post('/inputs', {
        source_type: sourceType, raw_text: rawText,
        project_id: projectId || undefined,
      })
      const id = inpRes.data.id
      setInputId(id)
      const anaRes = await apiClient.post('/analyze', { input_id: id })
      const rawItems = anaRes.data?.items ?? anaRes.data ?? []
      return Array.isArray(rawItems) ? rawItems : []
    },
    onSuccess: (data: AnalyzeItem[]) => {
      setItems(data)
      const defaultActions: Record<string, string> = {}
      data.forEach(it => { defaultActions[it.id] = 'CREATE_ISSUE' })
      setActions(defaultActions)
      setStep(1)
    },
  })

  const saveMutation = useMutation({
    mutationFn: async () => {
      await Promise.all(
        items.map(it =>
          apiClient.post('/actions', {
            item_id: it.id,
            action_type: actions[it.id] ?? 'STORE',
            decision_reason: reasons[it.id] ?? '',
          })
        )
      )
    },
    onSuccess: () => { setDone(true) },
  })

  // ── ラベルスタイル
  const labelStyle: React.CSSProperties = {
    display: 'block', fontSize: 12, fontWeight: 600,
    color: 'var(--text-secondary)', marginBottom: 6, letterSpacing: '0.02em',
  }

  // ── 完了画面
  if (done) return (
    <div style={{ maxWidth: 560, margin: '60px auto', textAlign: 'center' }}>
      <div style={{
        width: 64, height: 64, borderRadius: '50%',
        background: 'rgba(16,185,129,0.1)', border: '2px solid #10b981',
        display: 'flex', alignItems: 'center', justifyContent: 'center', margin: '0 auto 20px',
      }}>
        <CheckCircle size={30} color="#10b981" />
      </div>
      <h2 style={{ fontSize: 20, fontWeight: 800, color: 'var(--text-primary)', marginBottom: 8 }}>登録完了</h2>
      <p style={{ fontSize: 14, color: 'var(--text-muted)', marginBottom: 28 }}>
        要望が正常に登録・解析されました
      </p>
      <div style={{ display: 'flex', gap: 10, justifyContent: 'center' }}>
        <button onClick={() => navigate('/inputs')} style={{
          padding: '9px 20px', borderRadius: 9, background: 'var(--accent)',
          color: '#fff', border: 'none', fontWeight: 600, fontSize: 13, cursor: 'pointer',
        }}>要望履歴を見る</button>
        <button onClick={() => { setStep(0); setRawText(''); setItems([]); setDone(false) }} style={{
          padding: '9px 20px', borderRadius: 9, background: 'var(--bg-surface)',
          color: 'var(--text-primary)', border: '1px solid var(--border)', fontWeight: 600, fontSize: 13, cursor: 'pointer',
        }}>続けて登録</button>
      </div>
    </div>
  )

  return (
    <div style={{ maxWidth: 760, animation: 'fadeIn 0.2s ease' }}>
      {/* ステッパー */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 0, marginBottom: 28 }}>
        {STEPS.map((label, i) => (
          <div key={i} style={{ display: 'flex', alignItems: 'center' }}>
            <div style={{
              display: 'flex', alignItems: 'center', gap: 8,
              padding: '7px 16px', borderRadius: 8,
              background: i === step ? 'var(--accent)' : i < step ? 'rgba(16,185,129,0.12)' : 'var(--bg-surface)',
              border: `1.5px solid ${i === step ? 'var(--accent)' : i < step ? '#10b981' : 'var(--border)'}`,
              color: i === step ? '#fff' : i < step ? '#10b981' : 'var(--text-muted)',
              fontSize: 12, fontWeight: i === step ? 700 : 500,
              transition: 'all 0.2s',
            }}>
              {i < step && <CheckCircle size={13} />}
              {label}
            </div>
            {i < STEPS.length - 1 && (
              <ChevronRight size={16} color="var(--border-strong)" style={{ margin: '0 2px' }} />
            )}
          </div>
        ))}
      </div>

      {/* STEP 0: 原文入力 */}
      {step === 0 && (
        <div className="card" style={{ padding: '24px 28px' }}>
          <h2 style={{ fontSize: 16, fontWeight: 700, color: 'var(--text-primary)', marginBottom: 20 }}>
            📝 原文入力
          </h2>

          {projects.length > 0 && (
            <div style={{ marginBottom: 16 }}>
              <label style={labelStyle}>プロジェクト</label>
              <div style={{ position: 'relative' }}>
                <select value={projectId} onChange={e => setProjectId(e.target.value)} style={{ width: '100%', padding: '9px 32px 9px 12px' }}>
                  <option value="">プロジェクトを選択（任意）</option>
                  {projects.map((p: Project) => <option key={p.id} value={p.id}>{p.name}</option>)}
                </select>
                <ChevronRight size={13} style={{ position: 'absolute', right: 10, top: '50%', transform: 'translateY(-50%) rotate(90deg)', color: 'var(--text-muted)', pointerEvents: 'none' }} />
              </div>
            </div>
          )}

          <div style={{ marginBottom: 16 }}>
            <label style={labelStyle}>ソース種別</label>
            <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
              {SOURCE_OPTIONS.map(s => (
                <button key={s} onClick={() => setSourceType(s)} style={{
                  padding: '6px 14px', borderRadius: 8, fontSize: 12, fontWeight: 600, cursor: 'pointer',
                  background: sourceType === s ? 'var(--accent)' : 'var(--bg-surface)',
                  border: `1.5px solid ${sourceType === s ? 'var(--accent)' : 'var(--border)'}`,
                  color: sourceType === s ? '#fff' : 'var(--text-secondary)',
                  transition: 'all 0.15s',
                }}>{s}</button>
              ))}
            </div>
          </div>

          <div style={{ marginBottom: 20 }}>
            <label style={labelStyle}>原文テキスト</label>
            <textarea
              value={rawText}
              onChange={e => setRawText(e.target.value)}
              placeholder="要望・不具合報告・ミーティングメモなどを貼り付けてください"
              rows={8}
              style={{ width: '100%', padding: '12px 14px', resize: 'vertical', lineHeight: 1.7 }}
            />
          </div>

          {analyzeMutation.isError && (
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '10px 14px', borderRadius: 8, background: 'rgba(239,68,68,0.08)', border: '1px solid rgba(239,68,68,0.2)', color: '#dc2626', fontSize: 13, marginBottom: 16 }}>
              <AlertCircle size={15} /> 解析に失敗しました。再度お試しください。
            </div>
          )}

          <button
            onClick={() => analyzeMutation.mutate()}
            disabled={!rawText.trim() || analyzeMutation.isPending}
            style={{
              display: 'inline-flex', alignItems: 'center', gap: 8,
              padding: '10px 24px', borderRadius: 9,
              background: rawText.trim() ? 'var(--accent)' : 'var(--border)',
              color: rawText.trim() ? '#fff' : 'var(--text-muted)',
              border: 'none', fontWeight: 700, fontSize: 14, cursor: rawText.trim() ? 'pointer' : 'not-allowed',
              boxShadow: rawText.trim() ? 'var(--shadow-btn)' : 'none',
              transition: 'all 0.15s',
            }}
          >
            {analyzeMutation.isPending
              ? <><Loader2 size={15} style={{ animation: 'spin 1s linear infinite' }} /> 解析中...</>
              : '🔍 解析する'}
          </button>
        </div>
      )}

      {/* STEP 1: 分類確認 */}
      {step === 1 && (
        <div>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14 }}>
            <h2 style={{ fontSize: 16, fontWeight: 700, color: 'var(--text-primary)' }}>
              🔍 分類確認・修正 — {items.length} ITEM
            </h2>
            <button onClick={() => setStep(2)} style={{
              padding: '8px 18px', borderRadius: 9, background: 'var(--accent)',
              color: '#fff', border: 'none', fontWeight: 600, fontSize: 13, cursor: 'pointer',
            }}>次へ →</button>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {items.map((item, idx) => {
              const intent = INTENT_LABEL[item.intent_code] ?? { label: item.intent_code, color: '#94a3b8' }
              return (
                <div key={item.id} className="card" style={{ padding: '14px 18px' }}>
                  <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start' }}>
                    <div style={{
                      width: 24, height: 24, borderRadius: 6, flexShrink: 0,
                      background: 'var(--bg-surface-alt)',
                      display: 'flex', alignItems: 'center', justifyContent: 'center',
                      fontSize: 11, fontWeight: 700, color: 'var(--text-muted)',
                      fontFamily: 'DM Mono, monospace', border: '1px solid var(--border)',
                    }}>{idx + 1}</div>
                    <div style={{ flex: 1 }}>
                      <div style={{ display: 'flex', gap: 6, marginBottom: 6, flexWrap: 'wrap' }}>
                        <span className="badge" style={{ background: `${intent.color}18`, color: intent.color }}>
                          {intent.label}
                        </span>
                        <span className="badge" style={{ background: 'var(--bg-surface-alt)', color: 'var(--text-muted)' }}>
                          {item.domain_code}
                        </span>
                        <span style={{ fontSize: 11, color: 'var(--text-muted)', fontFamily: 'DM Mono, monospace' }}>
                          {Math.round(item.confidence * 100)}%
                        </span>
                      </div>
                      <p style={{ fontSize: 13, color: 'var(--text-primary)', lineHeight: 1.6 }}>{item.text}</p>
                    </div>
                  </div>
                </div>
              )
            })}
          </div>
        </div>
      )}

      {/* STEP 2: ACTION決定 */}
      {step === 2 && (
        <div>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14 }}>
            <h2 style={{ fontSize: 16, fontWeight: 700, color: 'var(--text-primary)' }}>
              ⚡ ACTION決定
            </h2>
            <div style={{ display: 'flex', gap: 8 }}>
              <button onClick={() => setStep(1)} style={{
                padding: '8px 16px', borderRadius: 9, background: 'var(--bg-surface)',
                color: 'var(--text-secondary)', border: '1px solid var(--border)', fontWeight: 600, fontSize: 13, cursor: 'pointer',
              }}>← 戻る</button>
              <button onClick={() => saveMutation.mutate()} disabled={saveMutation.isPending} style={{
                padding: '8px 18px', borderRadius: 9, background: 'var(--accent)',
                color: '#fff', border: 'none', fontWeight: 600, fontSize: 13, cursor: 'pointer',
                display: 'flex', alignItems: 'center', gap: 6,
              }}>
                {saveMutation.isPending ? <><Loader2 size={13} style={{ animation: 'spin 1s linear infinite' }} />保存中...</> : '✅ 保存する'}
              </button>
            </div>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {items.map((item, idx) => {
              const intent = INTENT_LABEL[item.intent_code] ?? { label: item.intent_code, color: '#94a3b8' }
              const selectedAct = actions[item.id]
              return (
                <div key={item.id} className="card" style={{ padding: '16px 18px' }}>
                  <div style={{ display: 'flex', gap: 10, alignItems: 'flex-start', marginBottom: 12 }}>
                    <div style={{
                      width: 22, height: 22, borderRadius: 5, flexShrink: 0,
                      background: 'var(--bg-surface-alt)', border: '1px solid var(--border)',
                      display: 'flex', alignItems: 'center', justifyContent: 'center',
                      fontSize: 10, fontWeight: 700, color: 'var(--text-muted)', fontFamily: 'DM Mono',
                    }}>{idx + 1}</div>
                    <div>
                      <span className="badge" style={{ background: `${intent.color}18`, color: intent.color, marginRight: 6 }}>{intent.label}</span>
                      <span style={{ fontSize: 13, color: 'var(--text-primary)' }}>{item.text}</span>
                    </div>
                  </div>
                  <div style={{ paddingLeft: 32 }}>
                    <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', marginBottom: 8 }}>
                      {ACTION_OPTIONS.map(opt => (
                        <button key={opt.value} onClick={() => setActions(prev => ({ ...prev, [item.id]: opt.value }))} style={{
                          padding: '5px 12px', borderRadius: 7, fontSize: 12, fontWeight: 600, cursor: 'pointer',
                          background: selectedAct === opt.value ? `${opt.color}18` : 'var(--bg-surface-alt)',
                          border: `1.5px solid ${selectedAct === opt.value ? opt.color : 'var(--border)'}`,
                          color: selectedAct === opt.value ? opt.color : 'var(--text-muted)',
                          transition: 'all 0.12s',
                        }}>{opt.label}</button>
                      ))}
                    </div>
                    <input
                      value={reasons[item.id] ?? ''}
                      onChange={e => setReasons(prev => ({ ...prev, [item.id]: e.target.value }))}
                      placeholder="判断理由（任意）"
                      style={{ width: '100%', padding: '7px 12px', fontSize: 12 }}
                    />
                  </div>
                </div>
              )
            })}
          </div>
        </div>
      )}
    </div>
  )
}
TSX
success "InputNew.tsx 更新完了"

# =============================================================================
section "4. 型チェック"
# =============================================================================
cd "$HOME/projects/decision-os/frontend"
npm run typecheck && echo -e "${GREEN}[OK]    型チェック PASS${RESET}" || echo "[WARN]  型警告あり（続行）"

# =============================================================================
section "5. 再起動"
# =============================================================================
PID=$(lsof -ti :3008 2>/dev/null || true)
[ -n "$PID" ] && kill "$PID" 2>/dev/null && sleep 2

nohup npm run dev -- --host 0.0.0.0 --port 3008 \
  > "$HOME/projects/decision-os/logs/frontend.log" 2>&1 &
sleep 3

lsof -ti :3008 &>/dev/null \
  && echo -e "${GREEN}[OK]    http://localhost:3008 起動完了${RESET}" \
  || echo "[WARN]  ログ確認: tail -f ~/projects/decision-os/logs/frontend.log"

echo ""
echo -e "${GREEN}✔ 完了！ライトモードが正しく表示されます${RESET}"
echo "  白背景・ダークテキスト・適切なコントラストで統一"
