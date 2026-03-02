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
