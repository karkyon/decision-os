import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Zap, Loader2, FolderOpen, ChevronRight, LogOut, Plus } from 'lucide-react'
import apiClient from '@/api/client'
import ThemeToggle from '@/components/ThemeToggle'

interface Tenant {
  id: string
  slug: string
  name: string
  plan: string
}

interface Project {
  id: string
  name: string
  description?: string
  status: string
}

export default function WorkspaceSelect() {
  const [tenants, setTenants]   = useState<Tenant[]>([])
  const [projects, setProjects] = useState<Project[]>([])
  const [selectedTenant, setSelectedTenant] = useState<Tenant | null>(null)
  const [loading, setLoading]   = useState(true)
  const [projLoading, setProjLoading] = useState(false)
  const [userName, setUserName] = useState('')
  const navigate = useNavigate()

  useEffect(() => {
    loadTenants()
    loadMe()
  }, [])

  async function loadMe() {
    try {
      const res = await apiClient.get('/auth/me')
      setUserName(res.data.name || '')
    } catch {}
  }

  async function loadTenants() {
    try {
      const res = await apiClient.get('/tenants')
      setTenants(res.data)
      if (res.data.length === 1) {
        selectTenant(res.data[0])
      }
    } catch (e) {
      console.error(e)
    } finally {
      setLoading(false)
    }
  }

  async function selectTenant(tenant: Tenant) {
    setSelectedTenant(tenant)
    setProjLoading(true)
    try {
      const res = await apiClient.get('/projects')
      setProjects(res.data.filter((p: Project) => p.status !== 'archived'))
    } catch (e) {
      console.error(e)
    } finally {
      setProjLoading(false)
    }
  }

  function selectProject(project: Project) {
    // プロジェクトIDをlocalStorageに保存してダッシュボードへ
    localStorage.setItem('current_project_id', project.id)
    localStorage.setItem('current_project_name', project.name)
    localStorage.setItem('current_tenant_slug', selectedTenant?.slug || 'default')
    navigate('/')
  }

  function logout() {
    localStorage.removeItem('access_token')
    localStorage.removeItem('refresh_token')
    localStorage.removeItem('current_project_id')
    navigate('/login')
  }

  const planBadge: Record<string, { label: string; color: string }> = {
    free:       { label: 'Free',       color: '#6b7280' },
    pro:        { label: 'Pro',        color: '#6366f1' },
    enterprise: { label: 'Enterprise', color: '#f59e0b' },
  }

  return (
    <div style={{
      minHeight: '100vh',
      background: 'var(--bg-base)',
      display: 'flex', flexDirection: 'column',
      alignItems: 'center', justifyContent: 'center',
      padding: '24px 16px',
      position: 'relative',
    }}>
      {/* アクセントライン */}
      <div style={{
        position: 'fixed', top: 0, left: 0, right: 0, height: 3,
        background: 'linear-gradient(90deg, #6366f1, #8b5cf6, #ec4899)',
      }} />

      {/* ヘッダーバー */}
      <div style={{
        position: 'fixed', top: 0, left: 0, right: 0,
        height: 52, display: 'flex', alignItems: 'center',
        justifyContent: 'space-between', padding: '0 24px',
        borderBottom: '1px solid var(--border)',
        background: 'var(--bg-surface)',
        backdropFilter: 'blur(8px)',
        zIndex: 10,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <div style={{
            width: 28, height: 28, borderRadius: 8,
            background: 'linear-gradient(135deg, #6366f1, #8b5cf6)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <Zap size={14} color="#fff" />
          </div>
          <span style={{ fontWeight: 800, fontSize: 15, color: 'var(--text-primary)', letterSpacing: '-0.03em' }}>
            decision-os
          </span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          {userName && (
            <span style={{ fontSize: 13, color: 'var(--text-muted)' }}>{userName}</span>
          )}
          <ThemeToggle />
          <button
            onClick={logout}
            style={{
              display: 'flex', alignItems: 'center', gap: 6,
              padding: '6px 12px', borderRadius: 8,
              border: '1px solid var(--border)',
              background: 'transparent',
              color: 'var(--text-secondary)', fontSize: 13,
              cursor: 'pointer',
            }}
          >
            <LogOut size={13} /> ログアウト
          </button>
        </div>
      </div>

      {/* メインコンテンツ */}
      <div style={{ width: '100%', maxWidth: 640, marginTop: 52 }}>

        {/* テナント選択 */}
        {!selectedTenant && (
          <>
            <div style={{ textAlign: 'center', marginBottom: 32 }}>
              <h2 style={{ margin: '0 0 8px', fontSize: 22, fontWeight: 800, color: 'var(--text-primary)', letterSpacing: '-0.04em' }}>
                ワークスペースを選択
              </h2>
              <p style={{ margin: 0, fontSize: 14, color: 'var(--text-muted)' }}>
                所属するテナントを選択してください
              </p>
            </div>

            {loading ? (
              <div style={{ textAlign: 'center', padding: 48 }}>
                <Loader2 size={24} style={{ animation: 'spin 1s linear infinite', color: 'var(--text-muted)' }} />
              </div>
            ) : tenants.length === 0 ? (
              <div className="card" style={{ textAlign: 'center', padding: 48, color: 'var(--text-muted)' }}>
                <p>所属するテナントがありません</p>
              </div>
            ) : (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
                {tenants.map(tenant => {
                  const badge = planBadge[tenant.plan] || planBadge.free
                  return (
                    <div
                      key={tenant.id}
                      className="card"
                      onClick={() => selectTenant(tenant)}
                      style={{
                        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                        padding: '18px 20px', cursor: 'pointer',
                        border: '1px solid var(--border)',
                        transition: 'border-color 0.15s, box-shadow 0.15s',
                      }}
                      onMouseEnter={e => {
                        (e.currentTarget as HTMLDivElement).style.borderColor = '#6366f1'
                        ;(e.currentTarget as HTMLDivElement).style.boxShadow = '0 0 0 3px rgba(99,102,241,0.1)'
                      }}
                      onMouseLeave={e => {
                        (e.currentTarget as HTMLDivElement).style.borderColor = 'var(--border)'
                        ;(e.currentTarget as HTMLDivElement).style.boxShadow = 'none'
                      }}
                    >
                      <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
                        <div style={{
                          width: 40, height: 40, borderRadius: 10,
                          background: 'linear-gradient(135deg, #6366f1, #8b5cf6)',
                          display: 'flex', alignItems: 'center', justifyContent: 'center',
                          flexShrink: 0,
                        }}>
                          <span style={{ color: '#fff', fontWeight: 800, fontSize: 16 }}>
                            {tenant.name.charAt(0)}
                          </span>
                        </div>
                        <div>
                          <div style={{ fontWeight: 700, fontSize: 15, color: 'var(--text-primary)' }}>
                            {tenant.name}
                          </div>
                          <div style={{ fontSize: 12, color: 'var(--text-muted)', marginTop: 2 }}>
                            {tenant.slug}
                          </div>
                        </div>
                      </div>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                        <span style={{
                          fontSize: 11, fontWeight: 600, padding: '3px 8px',
                          borderRadius: 20, background: `${badge.color}18`,
                          color: badge.color,
                        }}>
                          {badge.label}
                        </span>
                        <ChevronRight size={16} color="var(--text-muted)" />
                      </div>
                    </div>
                  )
                })}
              </div>
            )}
          </>
        )}

        {/* プロジェクト選択 */}
        {selectedTenant && (
          <>
            <div style={{ marginBottom: 24 }}>
              <button
                onClick={() => { setSelectedTenant(null); setProjects([]) }}
                style={{
                  display: 'flex', alignItems: 'center', gap: 6,
                  background: 'transparent', border: 'none',
                  color: 'var(--text-muted)', fontSize: 13, cursor: 'pointer',
                  padding: '4px 0', marginBottom: 16,
                }}
              >
                ← {selectedTenant.name}
              </button>
              <h2 style={{ margin: '0 0 6px', fontSize: 22, fontWeight: 800, color: 'var(--text-primary)', letterSpacing: '-0.04em' }}>
                プロジェクトを選択
              </h2>
              <p style={{ margin: 0, fontSize: 14, color: 'var(--text-muted)' }}>
                作業するプロジェクトを選択してください
              </p>
            </div>

            {projLoading ? (
              <div style={{ textAlign: 'center', padding: 48 }}>
                <Loader2 size={24} style={{ animation: 'spin 1s linear infinite', color: 'var(--text-muted)' }} />
              </div>
            ) : projects.length === 0 ? (
              <div className="card" style={{ textAlign: 'center', padding: 48, color: 'var(--text-muted)' }}>
                <FolderOpen size={32} style={{ marginBottom: 12, opacity: 0.4 }} />
                <p style={{ margin: 0 }}>プロジェクトがありません</p>
              </div>
            ) : (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                {projects.map(project => (
                  <div
                    key={project.id}
                    className="card"
                    onClick={() => selectProject(project)}
                    style={{
                      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                      padding: '16px 20px', cursor: 'pointer',
                      border: '1px solid var(--border)',
                      transition: 'border-color 0.15s, box-shadow 0.15s',
                    }}
                    onMouseEnter={e => {
                      (e.currentTarget as HTMLDivElement).style.borderColor = '#6366f1'
                      ;(e.currentTarget as HTMLDivElement).style.boxShadow = '0 0 0 3px rgba(99,102,241,0.1)'
                    }}
                    onMouseLeave={e => {
                      (e.currentTarget as HTMLDivElement).style.borderColor = 'var(--border)'
                      ;(e.currentTarget as HTMLDivElement).style.boxShadow = 'none'
                    }}
                  >
                    <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
                      <div style={{
                        width: 36, height: 36, borderRadius: 9,
                        background: 'var(--bg-muted)',
                        display: 'flex', alignItems: 'center', justifyContent: 'center',
                        flexShrink: 0,
                      }}>
                        <FolderOpen size={16} color="#6366f1" />
                      </div>
                      <div>
                        <div style={{ fontWeight: 700, fontSize: 14, color: 'var(--text-primary)' }}>
                          {project.name}
                        </div>
                        {project.description && (
                          <div style={{ fontSize: 12, color: 'var(--text-muted)', marginTop: 2, maxWidth: 380,
                            overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                            {project.description}
                          </div>
                        )}
                      </div>
                    </div>
                    <ChevronRight size={16} color="var(--text-muted)" />
                  </div>
                ))}

                {/* 新規プロジェクト作成（Admin/PM向け） */}
                <div
                  className="card"
                  onClick={() => navigate('/projects')}
                  style={{
                    display: 'flex', alignItems: 'center', gap: 12,
                    padding: '14px 20px', cursor: 'pointer',
                    border: '1px dashed var(--border)',
                    background: 'transparent',
                    transition: 'border-color 0.15s',
                  }}
                  onMouseEnter={e => (e.currentTarget as HTMLDivElement).style.borderColor = '#6366f1'}
                  onMouseLeave={e => (e.currentTarget as HTMLDivElement).style.borderColor = 'var(--border)'}
                >
                  <Plus size={16} color="var(--text-muted)" />
                  <span style={{ fontSize: 13, color: 'var(--text-muted)' }}>新規プロジェクトを作成</span>
                </div>
              </div>
            )}
          </>
        )}
      </div>

      <style>{`@keyframes spin { to { transform: rotate(360deg) } }`}</style>
    </div>
  )
}
