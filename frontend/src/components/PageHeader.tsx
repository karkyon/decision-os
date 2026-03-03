/**
 * PageHeader.tsx — ページタイトル + 現在PJサブタイトル
 *
 * 使い方:
 *   <PageHeader title="ダッシュボード" />
 *   <PageHeader title="課題一覧" subtitle="フィルタ済み" />
 */
import { useCurrentProject } from '../hooks/useCurrentProject'
import { FolderOpen } from 'lucide-react'

interface Props {
  title: string
  subtitle?: string
}

export default function PageHeader({ title, subtitle }: Props) {
  const pj = useCurrentProject()

  return (
    <div style={{ marginBottom: 24 }}>
      <h1 style={{
        fontSize: 22, fontWeight: 800,
        color: 'var(--text-primary)',
        letterSpacing: '-0.03em', margin: 0,
      }}>
        {title}
      </h1>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginTop: 4 }}>
        {pj && (
          <span style={{
            display: 'inline-flex', alignItems: 'center', gap: 4,
            fontSize: 12, color: '#6366f1', fontWeight: 600,
          }}>
            <FolderOpen size={12} />
            {pj.name}
          </span>
        )}
        {subtitle && (
          <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>
            {subtitle}
          </span>
        )}
        {!pj && (
          <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>
            プロジェクト未選択
          </span>
        )}
      </div>
    </div>
  )
}
