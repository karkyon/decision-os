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
