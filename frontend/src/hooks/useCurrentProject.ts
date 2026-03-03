/**
 * useCurrentProject — 現在選択中PJをどのコンポーネントでも取得できるフック
 */
import { useState, useEffect } from 'react'

export interface CurrentProject {
  id: string
  name: string
}

export function useCurrentProject(): CurrentProject | null {
  const [pj, setPj] = useState<CurrentProject | null>(() => {
    const id   = localStorage.getItem('current_project_id')
    const name = localStorage.getItem('current_project_name')
    return id && name ? { id, name } : null
  })

  useEffect(() => {
    const handler = () => {
      const id   = localStorage.getItem('current_project_id')
      const name = localStorage.getItem('current_project_name')
      setPj(id && name ? { id, name } : null)
    }
    window.addEventListener('storage', handler)
    return () => window.removeEventListener('storage', handler)
  }, [])

  return pj
}
