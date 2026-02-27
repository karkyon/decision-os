/**
 * usePermission - RBAC 権限チェックフック
 * 
 * 権限マトリクス（設計書 F-090〜F-094）:
 * 操作          | Admin | PM  | Dev | Viewer
 * --------------|-------|-----|-----|--------
 * Input作成      |  ○   | ○  | ○  |  ×
 * 分類変更       |  ○   | ○  |  ×  |  ×
 * Action変更     |  ○   | ○  |  ×  |  ×
 * Issue作成      |  ○   | ○  | ○  |  ×
 * 辞書編集       |  ○   |  ×  |  ×  |  ×
 * ロール変更     |  ○   |  ×  |  ×  |  ×
 */

import { useAtomValue } from "jotai";
import { userAtom } from "../store/auth";

type Role = "admin" | "pm" | "dev" | "viewer";

const ROLE_HIERARCHY: Record<Role, number> = {
  admin: 4,
  pm: 3,
  dev: 2,
  viewer: 1,
};

export function usePermission() {
  const user = useAtomValue(userAtom);
  const role = (user?.role ?? "viewer") as Role;
  const level = ROLE_HIERARCHY[role] ?? 1;

  return {
    role,

    // ロール判定
    isAdmin: role === "admin",
    isPM: role === "pm",
    isDev: role === "dev",
    isViewer: role === "viewer",

    // 操作権限（設計書マトリクス準拠）
    canCreateInput: level >= 2,       // dev 以上
    canChangeClassification: level >= 3, // pm 以上
    canChangeAction: level >= 3,      // pm 以上
    canCreateIssue: level >= 2,       // dev 以上
    canEditIssue: level >= 2,         // dev 以上
    canDeleteIssue: level >= 4,       // admin のみ
    canEditDictionary: level >= 4,    // admin のみ
    canChangeRole: level >= 4,        // admin のみ
    canManageLabels: level >= 3,      // pm 以上
    canViewAll: level >= 1,           // 全員

    // 汎用チェック
    hasRole: (...roles: Role[]) => roles.includes(role),
    atLeast: (minRole: Role) => level >= ROLE_HIERARCHY[minRole],
  };
}
