import { Sun, Moon } from 'lucide-react'
import { useTheme } from '@/contexts/ThemeContext'

export default function ThemeToggle({ size = 'md' }: { size?: 'sm' | 'md' }) {
  const { theme, toggle } = useTheme()
  const isLight = theme === 'light'
  const px = size === 'sm' ? '6px 10px' : '7px 12px'

  return (
    <button
      onClick={toggle}
      title={isLight ? 'ダークモードに切り替え' : 'ライトモードに切り替え'}
      style={{
        display: 'inline-flex', alignItems: 'center', gap: 6,
        padding: px, borderRadius: 8,
        background: 'var(--bg-input)', border: '1px solid var(--border)',
        color: 'var(--text-secondary)', cursor: 'pointer',
        fontSize: 12, fontWeight: 500, transition: 'all 0.15s',
        fontFamily: 'DM Sans, sans-serif',
      }}
      onMouseEnter={e => {
        const el = e.currentTarget as HTMLButtonElement
        el.style.borderColor = 'var(--accent)'
        el.style.color = 'var(--accent)'
      }}
      onMouseLeave={e => {
        const el = e.currentTarget as HTMLButtonElement
        el.style.borderColor = 'var(--border)'
        el.style.color = 'var(--text-secondary)'
      }}
    >
      {isLight ? <Moon size={14} /> : <Sun size={14} />}
      {size === 'md' && <span>{isLight ? 'Dark' : 'Light'}</span>}
    </button>
  )
}
