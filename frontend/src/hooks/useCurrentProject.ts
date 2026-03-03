import { useState, useEffect } from 'react'

export function useCurrentProject() {
  const [projectId, setProjectId] = useState<string>(
    () => localStorage.getItem('current_project_id') ?? ''
  )
  const [projectName, setProjectName] = useState<string>(
    () => localStorage.getItem('current_project_name') ?? ''
  )

  useEffect(() => {
    const sync = () => {
      setProjectId(localStorage.getItem('current_project_id') ?? '')
      setProjectName(localStorage.getItem('current_project_name') ?? '')
    }
    // 同タブ: CustomEvent / 他タブ: storage event
    window.addEventListener('project-changed', sync)
    window.addEventListener('storage', sync)
    return () => {
      window.removeEventListener('project-changed', sync)
      window.removeEventListener('storage', sync)
    }
  }, [])

  return { projectId, projectName }
}
