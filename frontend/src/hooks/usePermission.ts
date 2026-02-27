import { authStore } from '../store/auth'

export type Role = 'admin' | 'pm' | 'dev' | 'viewer'

export function usePermission() {
  // authStore から role を取得（jotai 不使用）
  const user = (authStore as any).getUser?.() ?? null
  const role: Role = (user?.role as Role) ?? 'viewer'

  return {
    role,
    isAdmin:  role === 'admin',
    isPM:     role === 'admin' || role === 'pm',
    canEdit:  role === 'admin' || role === 'pm' || role === 'dev',
    canView:  true,
  }
}
