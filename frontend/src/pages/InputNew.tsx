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
  const [_inputId, setInputId] = useState('')
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
