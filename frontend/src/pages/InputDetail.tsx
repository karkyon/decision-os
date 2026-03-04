import { useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  ArrowLeft, Mail, Mic, Users, Bug, MoreHorizontal,
  ChevronDown, ChevronUp, ExternalLink, Loader2, AlertCircle,
} from 'lucide-react'
import apiClient from '@/api/client'

/* ── 型定義 ─────────────────────────────────────────────── */
interface InputRecord {
  id: string
  source_type: string
  raw_text: string
  author?: string
  author_name?: string
  created_at: string
  project_id?: string
}

interface ItemRecord {
  id: string
  text: string
  intent_code: string
  domain_code: string
  confidence: number
  position: number
  action?: ActionRecord
}

interface ActionRecord {
  id: string
  action_type: string
  decision_reason?: string
  issue_id?: string
  decided_at?: string
  created_at?: string
}

interface TraceResult {
  input: InputRecord
  items: ItemRecord[]
}

/* ── 定数 ────────────────────────────────────────────────── */
const SOURCE_META: Record<string, { icon: React.ElementType; label: string; color: string }> = {
  email:   { icon: Mail,           label: 'メール',   color: '#60a5fa' },
  voice:   { icon: Mic,            label: '音声',     color: '#a78bfa' },
  meeting: { icon: Users,          label: '会議',     color: '#34d399' },
  bug:     { icon: Bug,            label: 'バグ報告', color: '#f87171' },
  other:   { icon: MoreHorizontal, label: 'その他',   color: 'var(--text-muted)' },
}

const INTENT_LABEL: Record<string, { label: string; color: string }> = {
  REQ: { label: '要求',   color: '#818cf8' },
  BUG: { label: 'バグ',   color: '#f87171' },
  IMP: { label: '改善',   color: '#fbbf24' },
  QST: { label: '質問',   color: '#34d399' },
  FBK: { label: 'FBK',   color: 'var(--text-muted)' },
  INF: { label: '情報',   color: 'var(--text-secondary, #64748b)' },
  MIS: { label: '誤解',   color: '#f97316' },
  OTH: { label: 'その他', color: 'var(--text-secondary, #64748b)' },
}

const ACTION_LABEL: Record<string, { label: string; color: string; bg: string }> = {
  CREATE_ISSUE:  { label: '課題化',  color: '#818cf8', bg: 'rgba(99,102,241,0.15)' },
  ANSWER:        { label: '回答',    color: '#34d399', bg: 'rgba(52,211,153,0.15)' },
  STORE:         { label: '保存',    color: '#60a5fa', bg: 'rgba(59,130,246,0.15)' },
  REJECT:        { label: '却下',    color: '#f87171', bg: 'rgba(239,68,68,0.15)'  },
  HOLD:          { label: '保留',    color: '#fbbf24', bg: 'rgba(245,158,11,0.15)' },
  LINK_EXISTING: { label: '既存紐付', color: 'var(--text-muted)', bg: 'rgba(100,116,139,0.15)'},
}

/* ── データ取得 ──────────────────────────────────────────── */
async function fetchInputTrace(id: string): Promise<TraceResult> {
  // INPUT詳細 + そのINPUTから派生したITEM一覧を取得
  const [inpRes, itemsRes] = await Promise.all([
    apiClient.get(`/inputs/${id}`),
    apiClient.get(`/items?input_id=${id}`).catch(() => ({ data: [] })),
  ])

  const input: InputRecord = inpRes.data

  // items の正規化
  const rawItems = (() => {
    const d = itemsRes.data
    if (Array.isArray(d)) return d
    if (Array.isArray(d?.items)) return d.items
    return []
  })()

  // 各ITEMに紐づくACTIONを取得（並列）
  const items: ItemRecord[] = await Promise.all(
    rawItems.map(async (item: ItemRecord) => {
      try {
        const actRes = await Promise.race([
          apiClient.get(`/actions?item_id=${item.id}`),
          new Promise((_, reject) => setTimeout(() => reject(new Error('timeout')), 3000))
        ]) as any
        const actData = actRes.data
        const actions = Array.isArray(actData) ? actData
          : Array.isArray(actData?.items) ? actData.items : []
        return { ...item, action: actions[0] ?? undefined }
      } catch {
        return item
      }
    })
  )

  return { input, items: items.sort((a, b) => (a.position ?? 0) - (b.position ?? 0)) }
}

async function fetchIssue(issueId: string) {
  const res = await apiClient.get(`/issues/${issueId}`)
  return res.data
}

/* ── Issue インライン表示コンポーネント ─────────────────── */
function LinkedIssue({ issueId }: { issueId: string }) {
  const { data: issue, isLoading } = useQuery({
    queryKey: ['issue-mini', issueId],
    queryFn: () => fetchIssue(issueId),
  })

  if (isLoading) return (
    <span style={{ fontSize: 12, color: 'var(--text-secondary, #64748b)' }}>読み込み中...</span>
  )
  if (!issue) return null

  return (
    <Link
      to={`/issues/${issueId}`}
      style={{
        display: 'inline-flex', alignItems: 'center', gap: 6,
        padding: '4px 10px', borderRadius: 6,
        background: 'rgba(99,102,241,0.12)', border: '1px solid rgba(99,102,241,0.3)',
        color: '#818cf8', textDecoration: 'none', fontSize: 12, fontWeight: 500,
        marginTop: 6,
      }}
    >
      <ExternalLink size={11} />
      {issue.title ?? `ISSUE: ${issueId.slice(0, 8)}`}
    </Link>
  )
}

/* ── メインコンポーネント ────────────────────────────────── */
export default function InputDetail() {
  const { id } = useParams<{ id: string }>()
  const queryClient = useQueryClient()
  const [textExpanded, setTextExpanded] = useState(false)
  const [editingItemId, setEditingItemId] = useState<string | null>(null)
  const [editText, setEditText] = useState('')
  const [editIntent, setEditIntent] = useState('')
  const [editDomain, setEditDomain] = useState('')
  const [editingActionId, setEditingActionId] = useState<string | null>(null)
  const [selectedItems, setSelectedItems] = useState<Set<string>>(new Set())
  const [mergeMode, setMergeMode] = useState(false)
  const [lastClickedIdx, setLastClickedIdx] = useState<number | null>(null)

  // ── ITEM削除 ──
  const deleteItem = async (itemId: string) => {
    if (!window.confirm('このITEMを削除しますか？')) return
    try {
      await apiClient.delete(`/items/${itemId}`)
      setEditingItemId(null)
      queryClient.invalidateQueries({ queryKey: ['input-trace', id] })
    } catch { alert('削除失敗') }
  }

  // ── ACTION変更（PATCH or DELETE + POST） ──
  const changeAction = async (itemId: string, actionType: string, existingActionId?: string) => {
    try {
      if (existingActionId) {
        // 既存ACTIONを削除してから再作成
        await apiClient.delete(`/actions/${existingActionId}`)
      }
      await apiClient.post('/actions', { item_id: itemId, action_type: actionType })
      setEditingActionId(null)
      queryClient.invalidateQueries({ queryKey: ['input-trace', id] })
    } catch { alert('ACTION更新失敗') }
  }

  // ── マージ ──
  const mergeItems = async () => {
    if (selectedItems.size < 2) { alert('2件以上選択してください'); return }
    const allItems = trace!.items
    const sel = allItems.filter(it => selectedItems.has(it.id))
      .sort((a, b) => (a.position ?? 0) - (b.position ?? 0))
    const base = sel[0]
    const mergedText = sel.map(it => it.text).join('\n')
    try {
      // ベースITEMのテキストを更新
      await apiClient.patch(`/items/${base.id}`, { text: mergedText })
      // 残りを削除
      for (const it of sel.slice(1)) {
        await apiClient.delete(`/items/${it.id}`)
      }
      setSelectedItems(new Set())
      setMergeMode(false)
      setLastClickedIdx(null)
      queryClient.invalidateQueries({ queryKey: ['input-trace', id] })
    } catch { alert('マージ失敗') }
  }

  // ── マージモードのクリック ──
  const handleItemClick = (item: any, idx: number, e: React.MouseEvent) => {
    if (!mergeMode) return
    const newSel = new Set(selectedItems)
    if (e.shiftKey && lastClickedIdx !== null) {
      const allItems = trace!.items
      const from = Math.min(lastClickedIdx, idx)
      const to   = Math.max(lastClickedIdx, idx)
      for (let i = from; i <= to; i++) newSel.add(allItems[i].id)
    } else if (e.ctrlKey || e.metaKey) {
      if (newSel.has(item.id)) newSel.delete(item.id)
      else newSel.add(item.id)
    } else {
      if (newSel.has(item.id)) newSel.delete(item.id)
      else newSel.add(item.id)
    }
    setSelectedItems(newSel)
    setLastClickedIdx(idx)
  }

  const { data: trace, isLoading, isError } = useQuery({
    queryKey: ['input-trace', id],
    queryFn: () => fetchInputTrace(id!),
    enabled: !!id,
  })

  if (isLoading) return (
    <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-secondary, #64748b)' }}>
      <Loader2 size={24} style={{ margin: '0 auto 12px', display: 'block', animation: 'spin 1s linear infinite' }} />
      <style>{`@keyframes spin{to{transform:rotate(360deg)}}`}</style>
      解析連鎖を構築中...
    </div>
  )
  if (isError || !trace) return (
    <div style={{ padding: 40, textAlign: 'center', color: '#ef4444' }}>
      <AlertCircle size={20} style={{ marginBottom: 8, display: 'block', margin: '0 auto 8px' }} />
      データの取得に失敗しました
    </div>
  )

  const { input, items } = trace
  const src = SOURCE_META[input.source_type] ?? SOURCE_META['other']
  const SrcIcon = src.icon
  const issueCount = items.filter(it => it.action?.action_type === 'CREATE_ISSUE' && it.action?.issue_id).length

  return (
    <div style={{ maxWidth: 860 }}>
      {/* Back */}
      <Link
        to="/inputs"
        style={{ display: 'inline-flex', alignItems: 'center', gap: 6, color: 'var(--text-secondary, #64748b)', textDecoration: 'none', fontSize: 13, marginBottom: 20 }}
      >
        <ArrowLeft size={14} /> 要望履歴に戻る
      </Link>

      {/* ── INPUT カード ── */}
      <div className="card" style={{ padding: '20px 24px', marginBottom: 16 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 14 }}>
          <div style={{
            width: 36, height: 36, borderRadius: 8, flexShrink: 0,
            background: `${src.color}22`, display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <SrcIcon size={18} color={src.color} />
          </div>
          <div>
            <div style={{ fontSize: 11, color: src.color, fontWeight: 700, letterSpacing: '0.06em', textTransform: 'uppercase' }}>
              📄 INPUT — {src.label}
            </div>
            <div style={{ fontSize: 11, color: 'var(--text-secondary, #64748b)', fontFamily: 'DM Mono, monospace', marginTop: 2 }}>
              {new Date(input.created_at).toLocaleString('ja-JP')}
              {input.author_name || input.author ? `  /  ${input.author_name ?? input.author}` : ''}
            </div>
          </div>
          <div style={{ marginLeft: 'auto', display: 'flex', gap: 10 }}>
            <div style={{ textAlign: 'right' }}>
              <div style={{ fontSize: 11, color: 'var(--text-secondary, #64748b)' }}>分解 ITEM</div>
              <div style={{ fontSize: 18, fontWeight: 700, color: 'var(--text-muted)' }}>{items.length}</div>
            </div>
            <div style={{ textAlign: 'right' }}>
              <div style={{ fontSize: 11, color: 'var(--text-secondary, #64748b)' }}>発生課題</div>
              <div style={{ fontSize: 18, fontWeight: 700, color: '#818cf8' }}>{issueCount}</div>
            </div>
          </div>
        </div>

        {/* Raw text */}
        <div style={{
          background: 'var(--bg-muted)', borderRadius: 8, padding: '14px 16px',
          border: '1px solid var(--border)', position: 'relative',
        }}>
          <p style={{
            margin: 0, fontSize: 13, color: 'var(--text-primary)', lineHeight: 1.8,
            whiteSpace: 'pre-wrap',
            maxHeight: textExpanded ? 'none' : '120px',
            overflow: textExpanded ? 'visible' : 'hidden',
          }}>
            {input.raw_text}
          </p>
          {input.raw_text.length > 200 && (
            <button
              onClick={() => setTextExpanded(!textExpanded)}
              style={{
                marginTop: 8, background: 'none', border: 'none',
                color: '#6366f1', cursor: 'pointer', fontSize: 12,
                display: 'flex', alignItems: 'center', gap: 4, padding: 0,
              }}
            >
              {textExpanded ? <><ChevronUp size={13} /> 折りたたむ</> : <><ChevronDown size={13} /> 全文を表示</>}
            </button>
          )}
        </div>
      </div>

      {/* ── ITEM → ACTION → ISSUE 連鎖 ── */}
      <div style={{ marginBottom: 12 }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 12 }}>
          <h2 style={{ margin: 0, fontSize: 14, fontWeight: 700, color: 'var(--text-secondary, #64748b)', letterSpacing: '0.08em', textTransform: 'uppercase' }}>
            分解結果 — {items.length} ITEM
          </h2>
          <div style={{ display: 'flex', gap: 8 }}>
            {mergeMode ? (
              <>
                <span style={{ fontSize: 12, color: 'var(--text-muted)', alignSelf: 'center' }}>
                  {selectedItems.size}件選択（Shift/Ctrl+クリックで複数選択）
                </span>
                <button onClick={mergeItems} disabled={selectedItems.size < 2}
                  style={{ padding: '5px 12px', borderRadius: 6, fontSize: 12, fontWeight: 600,
                    background: selectedItems.size >= 2 ? '#6366f1' : 'var(--bg-muted)',
                    color: selectedItems.size >= 2 ? '#fff' : 'var(--text-muted)',
                    border: 'none', cursor: selectedItems.size >= 2 ? 'pointer' : 'default' }}>
                  マージ実行
                </button>
                <button onClick={() => { setMergeMode(false); setSelectedItems(new Set()); setLastClickedIdx(null) }}
                  style={{ padding: '5px 12px', borderRadius: 6, fontSize: 12, border: '1px solid var(--border)',
                    background: 'transparent', color: 'var(--text-muted)', cursor: 'pointer' }}>
                  キャンセル
                </button>
              </>
            ) : (
              <button onClick={() => setMergeMode(true)}
                style={{ padding: '5px 12px', borderRadius: 6, fontSize: 12, fontWeight: 600,
                  border: '1px solid var(--border)', background: 'transparent',
                  color: 'var(--text-secondary, #64748b)', cursor: 'pointer' }}>
                ⊕ マージ
              </button>
            )}
          </div>
        </div>

        {items.length === 0 ? (
          <div className="card" style={{ padding: '32px', textAlign: 'center', color: 'var(--text-secondary, #64748b)', fontSize: 13 }}>
            このINPUTはまだ解析されていません
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {items.map((item, idx) => {
              const isMergeSelected = selectedItems.has(item.id)
              const intent = INTENT_LABEL[item.intent_code] ?? { label: item.intent_code, color: 'var(--text-muted)' }
              const act = item.action ? (ACTION_LABEL[item.action.action_type] ?? null) : null

              return (
                <div
                  key={item.id}
                  className="card"
                  onClick={(e) => handleItemClick(item, idx, e)}
                  style={{
                    padding: '14px 18px',
                    cursor: mergeMode ? 'pointer' : 'default',
                    outline: isMergeSelected ? '2px solid #6366f1' : 'none',
                    background: isMergeSelected ? 'rgba(99,102,241,0.07)' : undefined,
                    transition: 'outline 0.1s, background 0.1s',
                  }}
                >
                  <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start' }}>
                    {/* Position number */}
                    <div style={{
                      width: 22, height: 22, borderRadius: 6, flexShrink: 0,
                      background: 'var(--bg-muted)',
                      display: 'flex', alignItems: 'center', justifyContent: 'center',
                      fontSize: 11, fontWeight: 700, color: 'var(--text-secondary, #64748b)',
                      fontFamily: 'DM Mono, monospace', marginTop: 1,
                    }}>
                      {idx + 1}
                    </div>

                    <div style={{ flex: 1 }}>
                      {/* Badges */}
                      <div style={{ display: 'flex', gap: 6, marginBottom: 6, flexWrap: 'wrap', alignItems: 'center' }}>
                        <span className="badge" style={{ background: `${intent.color}22`, color: intent.color }}>
                          {intent.label}
                        </span>
                        <span className="badge" style={{ background: 'rgba(100,116,139,0.15)', color: 'var(--text-muted)' }}>
                          {item.domain_code}
                        </span>
                        <span style={{ fontSize: 11, color: 'var(--text-secondary, #64748b)', fontFamily: 'DM Mono, monospace' }}>
                          信頼度 {Math.round(item.confidence * 100)}%
                        </span>
                      </div>

                      {/* Item text */}
                      {editingItemId === item.id ? (
                        <div style={{ marginBottom: 8 }}>
                          <textarea
                            value={editText}
                            onChange={e => setEditText(e.target.value)}
                            rows={2}
                            style={{
                              width: '100%', padding: '8px 10px', borderRadius: 6,
                              border: '1px solid var(--border)', background: 'var(--bg-input)',
                              color: 'var(--text-primary)', fontSize: 13, resize: 'vertical',
                              boxSizing: 'border-box',
                            }}
                          />
                          <div style={{ display: 'flex', gap: 8, marginTop: 6 }}>
                            <select value={editIntent} onChange={e => setEditIntent(e.target.value)}
                              style={{ fontSize: 12, padding: '3px 8px', borderRadius: 6, border: '1px solid var(--border)', background: 'var(--bg-input)', color: 'var(--text-primary)' }}>
                              {[['REQ','機能要望'],['BUG','不具合'],['IMP','改善提案'],['QST','質問'],['FBK','FBK'],['INF','情報提供'],['MIS','認識相違'],['OTH','その他']].map(([v,l]) => (
                                <option key={v} value={v}>{v} — {l}</option>
                              ))}
                            </select>
                            <select value={editDomain} onChange={e => setEditDomain(e.target.value)}
                              style={{ fontSize: 12, padding: '3px 8px', borderRadius: 6, border: '1px solid var(--border)', background: 'var(--bg-input)', color: 'var(--text-primary)' }}>
                              {[['UI','画面'],['API','API'],['DB','DB'],['AUTH','認証'],['PERF','性能'],['SEC','セキュリティ'],['OPS','運用'],['SPEC','仕様']].map(([v,l]) => (
                                <option key={v} value={v}>{v} — {l}</option>
                              ))}
                            </select>
                            <button onClick={async () => {
                              try {
                                await apiClient.patch(`/items/${item.id}`, { text: editText, intent_code: editIntent, domain_code: editDomain })
                                setEditingItemId(null)
                                queryClient.invalidateQueries({ queryKey: ['input-trace', id] })
                              } catch { alert('保存失敗') }
                            }} style={{ padding: '4px 12px', borderRadius: 6, background: '#6366f1', border: 'none', color: '#fff', cursor: 'pointer', fontSize: 12 }}>保存</button>
                            <button onClick={() => setEditingItemId(null)}
                              style={{ padding: '4px 12px', borderRadius: 6, border: '1px solid var(--border)', background: 'transparent', color: 'var(--text-muted)', cursor: 'pointer', fontSize: 12 }}>キャンセル</button>
                            <button onClick={() => deleteItem(item.id)}
                              style={{ padding: '4px 12px', borderRadius: 6, border: '1px solid #ef4444', background: 'transparent', color: '#ef4444', cursor: 'pointer', fontSize: 12, marginLeft: 'auto' }}>🗑 削除</button>
                          </div>
                        </div>
                      ) : (
                        <div style={{ display: 'flex', alignItems: 'flex-start', gap: 8, marginBottom: 8 }}>
                          <p style={{ margin: 0, flex: 1, fontSize: 13, color: 'var(--text-primary)', lineHeight: 1.6 }}>
                            {item.text}
                          </p>
                          <button onClick={() => { setEditingItemId(item.id); setEditText(item.text); setEditIntent(item.intent_code); setEditDomain(item.domain_code) }}
                            style={{ flexShrink: 0, background: 'none', border: 'none', color: 'var(--text-muted)', cursor: 'pointer', fontSize: 12, padding: '2px 6px' }}>
                            ✏️
                          </button>
                        </div>
                      )}

                      {/* Action */}
                      {item.action && act && (
                        <div style={{ borderTop: '1px solid var(--border)', paddingTop: 8, marginTop: 4 }}>
                          <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                            <span style={{ fontSize: 11, color: 'var(--text-secondary, #64748b)' }}>→ ACTION:</span>
                            <span className="badge" style={{ background: act.bg, color: act.color }}>
                              {act.label}
                            </span>
                            {item.action.decision_reason && (
                              <span style={{ fontSize: 12, color: 'var(--text-secondary, #64748b)', fontStyle: 'italic' }}>
                                "{item.action.decision_reason}"
                              </span>
                            )}
                          </div>

                          {/* 課題リンク */}
                          {item.action.action_type === 'CREATE_ISSUE' && item.action.issue_id && (
                            <LinkedIssue issueId={item.action.issue_id} />
                          )}
                        </div>
                      )}

                      {/* Action変更ボタン（既存ACTIONがある場合） */}
                      {item.action && editingActionId !== item.id && (
                        <div style={{ marginTop: 4 }}>
                          <button onClick={() => setEditingActionId(item.id)}
                            style={{ fontSize: 11, color: 'var(--text-muted)', background: 'none', border: '1px solid var(--border)', borderRadius: 4, cursor: 'pointer', padding: '2px 8px' }}>
                            ✏ 変更
                          </button>
                        </div>
                      )}
                      {(!item.action || editingActionId === item.id) && (
                        <div style={{ borderTop: '1px solid var(--border)', paddingTop: 8, marginTop: 4 }}>
                          {editingActionId !== item.id ? (
                            <button onClick={() => setEditingActionId(item.id)}
                              style={{ fontSize: 12, color: 'var(--accent)', background: 'none', border: 'none', cursor: 'pointer', padding: 0 }}>
                              ＋ ACTION を設定
                            </button>
                          ) : (
                            <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', alignItems: 'center' }}>
                              {[
                                { value: 'CREATE_ISSUE', label: '課題化', color: '#818cf8' },
                                { value: 'ANSWER',       label: '回答',   color: '#34d399' },
                                { value: 'STORE',        label: '保存',   color: '#60a5fa' },
                                { value: 'REJECT',       label: '却下',   color: '#f87171' },
                                { value: 'HOLD',         label: '保留',   color: '#fbbf24' },
                              ].map(opt => (
                                <button key={opt.value} onClick={() => changeAction(item.id, opt.value, item.action?.id)} style={{
                                  padding: '4px 12px', borderRadius: 20, fontSize: 12, fontWeight: 600,
                                  border: `1px solid ${opt.color}`, background: `${opt.color}22`,
                                  color: opt.color, cursor: 'pointer',
                                }}>{opt.label}</button>
                              ))}
                              <button onClick={() => setEditingActionId(null)}
                                style={{ fontSize: 12, color: 'var(--text-muted)', background: 'none', border: 'none', cursor: 'pointer' }}>
                                キャンセル
                              </button>
                            </div>
                          )}
                        </div>
                      )}
                    </div>
                  </div>
                </div>
              )
            })}
          </div>
        )}
      </div>
    </div>
  )
}
