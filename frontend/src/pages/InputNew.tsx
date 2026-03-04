import PageHeader from '../components/PageHeader';
import { useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { useCurrentProject } from '../hooks/useCurrentProject'
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
  const { projectId: currentProjectId } = useCurrentProject()
  // URLパラメータ優先、なければ現在選択中のプロジェクト
  const projectId = searchParams.get('project_id') ?? currentProjectId

  const [sourceType, setSourceType] = useState('email')
  const [text, setText] = useState('')
  const [occurredAt, setOccurredAt] = useState('')   // 発生日
  const [reporterId, setReporterId] = useState('')    // 担当者（要望発信者）
  const [step, setStep] = useState<1 | 2 | 3>(1)
  const [analyzedInputId, setAnalyzedInputId] = useState<string>('')
  const [analyzedItems, setAnalyzedItems] = useState<any[]>([])
  const [actionMap, setActionMap] = useState<Record<string, string>>({})
  const [mergeMode, setMergeMode] = useState(false)
  const [lastMergeIdx, setLastMergeIdx] = useState<number | null>(null)

  const { data: users = [] } = useQuery({ queryKey: ['users'], queryFn: fetchUsers })

  // ─── ITEM削除 ──────────────────────────────────────────────
  const deleteItem = (itemId: string) => {
    if (!window.confirm('このITEMを削除しますか？')) return
    setAnalyzedItems((prev: any[]) => prev.filter((it: any) => it.id !== itemId))
  }

  // ─── マージ ─────────────────────────────────────────────────
  const toggleMergeSelect = (_itemId: string, idx: number, e: React.MouseEvent) => {
    if (!mergeMode) return
    setAnalyzedItems((prev: any[]) => {
      const newItems = [...prev]
      if (e.shiftKey && lastMergeIdx !== null) {
        const from = Math.min(lastMergeIdx, idx)
        const to   = Math.max(lastMergeIdx, idx)
        for (let i = from; i <= to; i++) newItems[i] = { ...newItems[i], mergeSelected: true }
      } else {
        newItems[idx] = { ...newItems[idx], mergeSelected: !newItems[idx].mergeSelected }
      }
      return newItems
    })
    setLastMergeIdx(idx)
  }

  const executeMerge = () => {
    const selected = analyzedItems.filter((it: any) => it.mergeSelected)
    if (selected.length < 2) { alert('2件以上選択してください'); return }
    const sorted = [...selected].sort((a: any, b: any) => (a.position ?? 0) - (b.position ?? 0))
    const base = sorted[0]
    const mergedText = sorted.map((it: any) => it.text).join('\n')
    const selectedIds = new Set(sorted.map((it: any) => it.id))
    setAnalyzedItems((prev: any[]) => prev
      .filter((it: any) => it.id === base.id || !selectedIds.has(it.id))
      .map((it: any) => it.id === base.id ? { ...it, text: mergedText, mergeSelected: false } : it)
      .map((it: any, i: number) => ({ ...it, position: i + 1 }))
    )
    setMergeMode(false)
    setLastMergeIdx(null)
  }

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
    onSuccess: ({ inputId, items }) => {
      setAnalyzedInputId(inputId)
      setAnalyzedItems(items?.items ?? items ?? [])
      setStep(2)
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
      <PageHeader title="要望登録" />
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

      {/* ── STEP 2: 分類確認・修正 ── */}
      {step === 2 && (
        <div style={{ maxWidth: 760, marginTop: 24 }}>
          <div style={{
            background: 'var(--bg-surface)', border: '1px solid var(--border)',
            borderRadius: 14, padding: '24px 28px',
          }}>
            <h2 style={{ margin: '0 0 20px', fontSize: 16, fontWeight: 700, color: 'var(--text-primary)' }}>
              🧩 分解結果 — {analyzedItems.length} ITEM
            </h2>
            <div style={{ display: 'flex', gap: 8 }}>
              {mergeMode ? (<>
                <span style={{ fontSize: 12, alignSelf: 'center', color: '#64748b' }}>
                  {analyzedItems.filter((it: any) => it.mergeSelected).length}件選択（Shift/Ctrl+クリック）
                </span>
                <button onClick={executeMerge}
                  disabled={analyzedItems.filter((it: any) => it.mergeSelected).length < 2}
                  style={{ padding: '5px 12px', borderRadius: 6, fontSize: 12, fontWeight: 600,
                    background: analyzedItems.filter((it: any) => it.mergeSelected).length >= 2 ? '#6366f1' : '#cbd5e1',
                    color: '#fff', border: 'none', cursor: 'pointer' }}>マージ実行</button>
                <button onClick={() => { setMergeMode(false); setAnalyzedItems((prev: any[]) => prev.map(it => ({ ...it, mergeSelected: false }))) }}
                  style={{ padding: '5px 12px', borderRadius: 6, fontSize: 12,
                    border: '1px solid #cbd5e1', background: 'transparent', cursor: 'pointer' }}>キャンセル</button>
              </>) : (
                <button onClick={() => setMergeMode(true)}
                  style={{ padding: '5px 12px', borderRadius: 6, fontSize: 12,
                    border: '1px solid #cbd5e1', background: 'transparent', cursor: 'pointer' }}>⊕ マージ</button>
              )}
            </div>
            <p style={{ fontSize: 13, color: 'var(--text-muted)', marginBottom: 20 }}>
              各ITEMの Intent / Domain を確認・修正してください。
            </p>

            <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginBottom: 24 }}>
              {analyzedItems.map((item: any, idx: number) => (
                <div
                  key={item.id}
                  onClick={(e) => toggleMergeSelect(item.id, idx, e)}
                  style={{
                    cursor: mergeMode ? 'pointer' : 'default',
                    outline: item.mergeSelected ? '2px solid #6366f1' : 'none',
                  border: '1px solid var(--border)', borderRadius: 10,
                  padding: '14px 18px', background: 'var(--bg-surface)',
                }}>
                  <div style={{ display: 'flex', gap: 10, alignItems: 'flex-start' }}>
                    <div style={{
                      width: 22, height: 22, borderRadius: 6, flexShrink: 0,
                      background: 'var(--bg-muted)',
                      display: 'flex', alignItems: 'center', justifyContent: 'center',
                      fontSize: 11, fontWeight: 700, color: 'var(--text-muted)',
                    }}>{idx + 1}</div>
                    <div style={{ flex: 1 }}>
                      <textarea
                        value={item.text}
                        onChange={e => {
                          const updated = [...analyzedItems]
                          updated[idx] = { ...updated[idx], text: e.target.value }
                          setAnalyzedItems(updated)
                        }}
                        rows={2}
                        style={{
                          width: '100%', marginBottom: 10, padding: '8px 10px',
                          borderRadius: 6, border: '1px solid var(--border)',
                          background: 'var(--bg-input)', color: 'var(--text-primary)',
                          fontSize: 13, lineHeight: 1.6, resize: 'vertical',
                          boxSizing: 'border-box',
                        }}
                      />
                      <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'center' }}>
                        <label style={{ fontSize: 12, color: 'var(--text-muted)' }}>Intent:</label>
                        <select
                          defaultValue={item.intent_code}
                          onChange={e => {
                            const updated = [...analyzedItems]
                            updated[idx] = { ...updated[idx], intent_code: e.target.value }
                            setAnalyzedItems(updated)
                          }}
                          style={{ fontSize: 12, padding: '3px 8px', borderRadius: 6, border: '1px solid var(--border)', background: 'var(--bg-input)', color: 'var(--text-primary)' }}
                        >
                                                    <option key="REQ" value="REQ">REQ — 機能要望</option>
                          <option key="BUG" value="BUG">BUG — 不具合報告</option>
                          <option key="IMP" value="IMP">IMP — 改善提案</option>
                          <option key="QST" value="QST">QST — 質問</option>
                          <option key="FBK" value="FBK">FBK — フィードバック</option>
                          <option key="INF" value="INF">INF — 情報提供</option>
                          <option key="MIS" value="MIS">MIS — 認識相違</option>
                          <option key="OTH" value="OTH">OTH — その他</option>
                        </select>
                        <label style={{ fontSize: 12, color: 'var(--text-muted)' }}>Domain:</label>
                        <select
                          defaultValue={item.domain_code}
                          onChange={e => {
                            const updated = [...analyzedItems]
                            updated[idx] = { ...updated[idx], domain_code: e.target.value }
                            setAnalyzedItems(updated)
                          }}
                          style={{ fontSize: 12, padding: '3px 8px', borderRadius: 6, border: '1px solid var(--border)', background: 'var(--bg-input)', color: 'var(--text-primary)' }}
                        >
                                                    <option key="UI" value="UI">UI   — 画面・インターフェース</option>
                          <option key="API" value="API">API  — バックエンドAPI</option>
                          <option key="DB" value="DB">DB   — データベース</option>
                          <option key="AUTH" value="AUTH">AUTH — 認証・権限</option>
                          <option key="PERF" value="PERF">PERF — パフォーマンス</option>
                          <option key="SEC" value="SEC">SEC  — セキュリティ</option>
                          <option key="OPS" value="OPS">OPS  — 運用・インフラ</option>
                          <option key="SPEC" value="SPEC">SPEC — 仕様・設計</option>
                        </select>
                        <span style={{ fontSize: 11, color: 'var(--text-muted)', fontFamily: 'DM Mono, monospace' }}>
                          信頼度 {Math.round((item.confidence ?? 0) * 100)}%
                        </span>
                      </div>
                      {/* 削除ボタン */}
                      <div style={{ marginTop: 8, display: 'flex', justifyContent: 'flex-end' }}>
                        <button
                          onClick={(e) => { e.stopPropagation(); deleteItem(item.id) }}
                          style={{
                            padding: '3px 10px', borderRadius: 5, fontSize: 11,
                            border: '1px solid #ef4444', background: 'transparent',
                            color: '#ef4444', cursor: 'pointer', opacity: 0.7,
                          }}
                          onMouseEnter={e => (e.currentTarget.style.opacity = '1')}
                          onMouseLeave={e => (e.currentTarget.style.opacity = '0.7')}
                        >🗑 削除</button>
                      </div>
                    </div>
                  </div>
                </div>
              ))}
            </div>

            <div style={{ display: 'flex', gap: 10 }}>
              <button onClick={() => setStep(1)} style={{
                padding: '10px 20px', borderRadius: 8,
                border: '1px solid var(--border)', background: 'transparent',
                color: 'var(--text-muted)', cursor: 'pointer', fontSize: 13,
              }}>← 戻る</button>
              <button onClick={() => setStep(3)} style={{
                padding: '10px 24px', borderRadius: 8,
                background: '#6366f1', border: 'none',
                color: '#fff', cursor: 'pointer', fontSize: 13, fontWeight: 600,
              }}>ACTION決定へ →</button>
            </div>
          </div>
        </div>
      )}

      {/* ── STEP 3: ACTION決定 ── */}
      {step === 3 && (
        <div style={{ maxWidth: 760, marginTop: 24 }}>
          <div style={{
            background: 'var(--bg-surface)', border: '1px solid var(--border)',
            borderRadius: 14, padding: '24px 28px',
          }}>
            <h2 style={{ margin: '0 0 20px', fontSize: 16, fontWeight: 700, color: 'var(--text-primary)' }}>
              ⚡ ACTION決定 — 各ITEMの対応を選択
            </h2>

            <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginBottom: 24 }}>
              {analyzedItems.map((item: any, idx: number) => {
                const ACTION_OPTIONS = [
                  { value: 'CREATE_ISSUE',  label: '課題化',   color: '#818cf8' },
                  { value: 'ANSWER',        label: '回答',     color: '#34d399' },
                  { value: 'STORE',         label: '保存',     color: '#60a5fa' },
                  { value: 'REJECT',        label: '却下',     color: '#f87171' },
                  { value: 'HOLD',          label: '保留',     color: '#fbbf24' },
                ]
                const selected = actionMap[item.id] ?? ''
                return (
                  <div key={item.id} style={{
                    border: '1px solid var(--border)', borderRadius: 10,
                    padding: '14px 18px', background: 'var(--bg-surface)',
                  }}>
                    <p style={{ margin: '0 0 10px', fontSize: 13, color: 'var(--text-primary)', lineHeight: 1.6 }}>
                      <span style={{ fontSize: 11, color: 'var(--text-muted)', marginRight: 8 }}>#{idx + 1}</span>
                      {item.text}
                    </p>
                    <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                      {ACTION_OPTIONS.map(opt => (
                        <button
                          key={opt.value}
                          onClick={() => setActionMap(prev => ({ ...prev, [item.id]: opt.value }))}
                          style={{
                            padding: '5px 14px', borderRadius: 20, fontSize: 12, fontWeight: 600,
                            border: `2px solid ${selected === opt.value ? opt.color : 'var(--border)'}`,
                            background: selected === opt.value ? `${opt.color}22` : 'transparent',
                            color: selected === opt.value ? opt.color : 'var(--text-muted)',
                            cursor: 'pointer', transition: 'all 0.15s',
                          }}
                        >{opt.label}</button>
                      ))}
                    </div>
                  </div>
                )
              })}
            </div>

            <div style={{ display: 'flex', gap: 10 }}>
              <button onClick={() => setStep(2)} style={{
                padding: '10px 20px', borderRadius: 8,
                border: '1px solid var(--border)', background: 'transparent',
                color: 'var(--text-muted)', cursor: 'pointer', fontSize: 13,
              }}>← 戻る</button>
              <button onClick={async () => {
                // ACTION を一括保存 → CREATE_ISSUEは convert も呼ぶ
                await Promise.all(
                  Object.entries(actionMap).map(async ([itemId, actionType]) => {
                    try {
                      const res = await apiClient.post('/actions', { item_id: itemId, action_type: actionType })
                      const actionId = res.data?.id ?? res.data?.action_id
                      if (actionType === 'CREATE_ISSUE' && actionId) {
                        await apiClient.post(`/actions/${actionId}/convert`).catch(() => {})
                      }
                    } catch {}
                  })
                )
                navigate(`/inputs/${analyzedInputId}`)
              }} style={{
                padding: '10px 24px', borderRadius: 8,
                background: '#6366f1', border: 'none',
                color: '#fff', cursor: 'pointer', fontSize: 13, fontWeight: 600,
              }}>✅ 保存して完了</button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
