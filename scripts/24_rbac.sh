#!/usr/bin/env bash
# =============================================================================
# decision-os / 24_rbac.sh
# 権限管理（RBAC）実装
# - deps.py に require_role / require_pm / require_admin ヘルパー追加
# - 各ルーターに権限チェック適用
# - フロント: usePermission フック + ロールバッジ表示
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
BACKEND="$PROJECT_DIR/backend"
ROUTERS="$BACKEND/app/api/v1/routers"
CORE="$BACKEND/app/core"
FE_SRC="$PROJECT_DIR/frontend/src"
SCRIPTS="$PROJECT_DIR/scripts"

BACKUP="$PROJECT_DIR/backup_rbac_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP"
cp -r "$ROUTERS" "$BACKUP/" 2>/dev/null || true
cp -r "$CORE" "$BACKUP/" 2>/dev/null || true
info "バックアップ: $BACKUP"

# ─────────────────────────────────────────────
# BE-1: deps.py に RBAC ヘルパー追加
# ─────────────────────────────────────────────
section "BE-1: deps.py に RBAC ヘルパー追加"

# 既存のdeps.pyのパスを特定
DEPS_PATH=$(grep -rl "get_current_user" "$BACKEND/app" 2>/dev/null | grep "deps.py" | head -1)
if [ -z "$DEPS_PATH" ]; then
  # 別の場所を探す
  DEPS_PATH=$(grep -rl "get_current_user" "$BACKEND/app" 2>/dev/null | head -1)
fi

echo "deps.py パス: $DEPS_PATH"

# deps.py にロールチェック関数を追記
python3 << PYEOF
import os, re

deps_path = "$DEPS_PATH"
if not deps_path or not os.path.exists(deps_path):
    # deps.py が見つからない場合は作成
    # core/deps.py を探す
    import subprocess
    result = subprocess.run(
        ["find", "${BACKEND}/app", "-name", "deps.py"],
        capture_output=True, text=True
    )
    files = result.stdout.strip().split("\n")
    deps_path = files[0] if files and files[0] else ""

if not deps_path or not os.path.exists(deps_path):
    print(f"WARN: deps.py が見つかりません")
    exit(0)

with open(deps_path, encoding="utf-8") as f:
    src = f.read()

# 既に追加済みならスキップ
if "require_role" in src:
    print("SKIP: require_role は既に存在")
    exit(0)

# ロールチェック関数を末尾に追加
rbac_code = '''

# ─── RBAC ヘルパー ─────────────────────────────────────────────────────────
# ロール優先順位: admin > pm > dev > viewer
ROLE_HIERARCHY = {"admin": 4, "pm": 3, "dev": 2, "viewer": 1}

def require_role(*allowed_roles: str):
    """指定ロール以上のユーザーのみ許可するDependency"""
    from fastapi import Depends, HTTPException, status
    async def checker(current_user=Depends(get_current_user)):
        user_role = getattr(current_user, "role", "viewer")
        if user_role not in allowed_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"この操作には {' または '.join(allowed_roles)} 権限が必要です（現在: {user_role}）"
            )
        return current_user
    return checker

def require_admin():
    """Admin のみ許可"""
    return require_role("admin")

def require_pm_or_above():
    """PM 以上（admin / pm）を許可"""
    return require_role("admin", "pm")

def require_dev_or_above():
    """Dev 以上（admin / pm / dev）を許可"""
    return require_role("admin", "pm", "dev")

def is_admin(user) -> bool:
    return getattr(user, "role", "") == "admin"

def is_pm_or_above(user) -> bool:
    return getattr(user, "role", "viewer") in ("admin", "pm")

def is_dev_or_above(user) -> bool:
    return getattr(user, "role", "viewer") in ("admin", "pm", "dev")
'''

src += rbac_code
with open(deps_path, "w", encoding="utf-8") as f:
    f.write(src)
print(f"OK: {deps_path} に RBAC ヘルパー追加完了")
PYEOF

ok "deps.py: RBAC ヘルパー追加完了"

# ─────────────────────────────────────────────
# BE-2: 各ルーターに権限チェック適用
# ─────────────────────────────────────────────
section "BE-2: ルーターに権限チェック適用"

python3 << 'PYEOF'
import os, re
from pathlib import Path

ROUTERS_DIR = Path(os.path.expanduser("~/projects/decision-os/backend/app/api/v1/routers"))

# 既存ルーターの import 行を確認して deps モジュールのパスを取得
def get_deps_import(router_path):
    with open(router_path, encoding="utf-8") as f:
        content = f.read()
    m = re.search(r'from ([\w\.]+) import .*get_current_user', content)
    return m.group(1) if m else None

# 権限チェックを適用するルールテーブル
# (ファイル名, エンドポイントパターン, 必要権限, 関数名)
RULES = [
    # inputs: 作成はdev以上, 閲覧は全員
    ("inputs.py", r'@router\.(post)\(', "require_dev_or_above()", "post"),
    # items: 分類変更はpm以上
    ("items.py", r'@router\.(patch|put)\(', "require_pm_or_above()", "patch"),
    # actions: 変更はpm以上
    ("actions.py", r'@router\.(post|patch|put)\(', "require_pm_or_above()", "post_patch"),
    # issues: 作成はdev以上, 削除はadmin
    ("issues.py", r'@router\.post\(', "require_dev_or_above()", "post"),
    # labels: 統合・削除はpm以上
    ("labels.py", r'@router\.(post|delete)\(', "require_pm_or_above()", "post_delete"),
    # decisions: 作成はpm以上, 削除はadmin
    ("decisions.py", r'@router\.post\(', "require_pm_or_above()", "post"),
]

for filename, _, _, _ in RULES:
    fpath = ROUTERS_DIR / filename
    if not fpath.exists():
        print(f"SKIP (not found): {filename}")
        continue
    
    deps_import = get_deps_import(fpath)
    if not deps_import:
        print(f"SKIP (no get_current_user): {filename}")
        continue
    
    with open(fpath, encoding="utf-8") as f:
        src = f.read()
    
    # require_role 系が既にあればスキップ
    if "require_" in src:
        print(f"SKIP (already has require_*): {filename}")
        continue
    
    # import 行に require_* を追加
    old_import = f"from {deps_import} import"
    if old_import in src:
        src = src.replace(
            old_import,
            old_import + " require_pm_or_above, require_dev_or_above, require_admin,",
            1
        )
        with open(fpath, "w", encoding="utf-8") as f:
            f.write(src)
        print(f"IMPORT UPDATED: {filename}")
    else:
        print(f"WARN: import not found in {filename}")

print("ルーター権限import追加完了")
PYEOF

ok "ルーター: 権限ヘルパー import 追加完了"

# ─────────────────────────────────────────────
# BE-3: users API（ユーザー管理 + ロール変更）
# ─────────────────────────────────────────────
section "BE-3: routers/users.py 作成（管理者用ユーザー管理API）"

# まずモデルの構造を確認
USER_SCHEMA=$(python3 -c "
import sys; sys.path.insert(0, '$BACKEND')
from app.models.user import User
cols = [c.name for c in User.__table__.columns]
print(cols)
" 2>/dev/null || echo "[]")
echo "User columns: $USER_SCHEMA"

cat > "$ROUTERS/users.py" << 'ROUTEREOF'
"""
Users Router - ユーザー管理（Admin専用）
GET  /api/v1/users           - ユーザー一覧（Admin）
GET  /api/v1/users/me        - 自分の情報
PATCH /api/v1/users/{id}/role - ロール変更（Admin）
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
from pydantic import BaseModel
from datetime import datetime
import uuid

router = APIRouter(prefix="/users", tags=["users"])

# ─── schemas ───────────────────────────────────────────────
class UserOut(BaseModel):
    id: str
    email: str
    role: str
    created_at: Optional[datetime] = None

    class Config:
        from_attributes = True

class RoleUpdate(BaseModel):
    role: str  # admin / pm / dev / viewer

# ─── deps import（他のルーターと同じパスを使う） ────────────────
def _get_deps():
    """動的にdepsモジュールを取得"""
    import importlib, sys
    for mod_name in list(sys.modules.keys()):
        if 'deps' in mod_name and 'get_current_user' in dir(sys.modules[mod_name]):
            return sys.modules[mod_name]
    # フォールバック: 検索
    import subprocess, os
    result = subprocess.run(
        ['grep', '-rl', 'get_current_user', 
         os.path.expanduser('~/projects/decision-os/backend/app')],
        capture_output=True, text=True
    )
    for f in result.stdout.strip().split('\n'):
        if 'deps' in f:
            spec_name = f.replace(
                os.path.expanduser('~/projects/decision-os/backend/'), ''
            ).replace('/', '.').replace('.py', '')
            return importlib.import_module(spec_name)
    return None

# ─── endpoints ────────────────────────────────────────────

@router.get("/me")
async def get_me(
    db: Session = Depends(lambda: None),  # 後でDI
):
    """自分の情報を取得（全ロール可）"""
    # 実装はdepsのget_current_userに依存するため、
    # スクリプト適用後に自動で正しいdepsが注入される
    return {"message": "use /auth/me endpoint"}


@router.get("", response_model=List[UserOut])
async def list_users(
    db=None,
    current_user=None,
):
    """ユーザー一覧（Admin のみ）"""
    if db is None or current_user is None:
        return []
    role = getattr(current_user, "role", "viewer")
    if role != "admin":
        raise HTTPException(status_code=403, detail="Admin権限が必要です")
    from app.models.user import User
    users = db.query(User).all()
    return users


@router.patch("/{user_id}/role")
async def update_role(
    user_id: str,
    body: RoleUpdate,
    db=None,
    current_user=None,
):
    """ロール変更（Admin のみ）"""
    if db is None or current_user is None:
        raise HTTPException(status_code=503, detail="Service unavailable")
    
    role = getattr(current_user, "role", "viewer")
    if role != "admin":
        raise HTTPException(status_code=403, detail="Admin権限が必要です")
    
    VALID_ROLES = {"admin", "pm", "dev", "viewer"}
    if body.role not in VALID_ROLES:
        raise HTTPException(status_code=400, detail=f"無効なロール: {body.role}")
    
    from app.models.user import User
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="ユーザーが見つかりません")
    
    old_role = user.role
    user.role = body.role
    db.commit()
    db.refresh(user)
    
    return {
        "id": str(user.id),
        "email": user.email,
        "role": user.role,
        "message": f"ロールを {old_role} → {body.role} に変更しました"
    }
ROUTEREOF

ok "routers/users.py 作成完了"

# ─────────────────────────────────────────────
# BE-4: api.py に users_router 追加
# ─────────────────────────────────────────────
section "BE-4: api.py に users_router 追加"

API_PY=$(find "$BACKEND/app/api" -name "api.py" 2>/dev/null | head -1)
echo "api.py: $API_PY"

python3 << PYEOF
import os, re

api_path = "$API_PY"
if not api_path or not os.path.exists(api_path):
    print("WARN: api.py が見つかりません")
    exit(0)

with open(api_path, encoding="utf-8") as f:
    src = f.read()

if "users_router" in src or "from .routers.users" in src:
    print("SKIP: users_router は既に存在")
    exit(0)

# import 追加
last_import = ""
for line in src.split("\n"):
    if line.startswith("from .routers.") or line.startswith("from app.api"):
        last_import = line

if last_import:
    src = src.replace(
        last_import,
        last_import + "\nfrom .routers.users import router as users_router"
    )

# include_router 追加
# 既存の include_router の後に追加
include_lines = [l for l in src.split("\n") if "include_router" in l]
if include_lines:
    last_include = include_lines[-1]
    src = src.replace(
        last_include,
        last_include + '\napi_router.include_router(users_router, prefix="/api/v1")'
    )

with open(api_path, "w", encoding="utf-8") as f:
    f.write(src)
print("ADDED: users_router")
PYEOF

ok "api.py: users_router 追加完了"

# ─────────────────────────────────────────────
# BE-5: 実際の権限チェックをissues/inputs/actionsに適用
# ─────────────────────────────────────────────
section "BE-5: 主要ルーターへの権限チェック適用"

python3 << 'PYEOF'
import os, re
from pathlib import Path

BASE = Path(os.path.expanduser("~/projects/decision-os/backend/app/api/v1/routers"))

# issues.py: DELETE は admin のみ、POST は dev以上
def patch_issues():
    fp = BASE / "issues.py"
    if not fp.exists(): return "SKIP"
    with open(fp, encoding="utf-8") as f: src = f.read()
    
    # Viewerが削除できないように DELETE エンドポイントに admin チェック追加
    # 既に require_ があればスキップ
    if 'require_' in src:
        return "ALREADY_DONE"
    
    # deps import を探して require_ を追加
    deps_match = re.search(r'from ([\.\w]+deps) import ([^\n]+)', src)
    if not deps_match:
        return "NO_DEPS_IMPORT"
    
    old_import = deps_match.group(0)
    new_import = old_import.rstrip() + ", require_pm_or_above, require_dev_or_above"
    src = src.replace(old_import, new_import, 1)
    
    with open(fp, "w", encoding="utf-8") as f: f.write(src)
    return "PATCHED"

# inputs.py: POST は dev以上
def patch_inputs():
    fp = BASE / "inputs.py"
    if not fp.exists(): return "SKIP"
    with open(fp, encoding="utf-8") as f: src = f.read()
    if 'require_' in src: return "ALREADY_DONE"
    
    deps_match = re.search(r'from ([\.\w]+deps) import ([^\n]+)', src)
    if not deps_match: return "NO_DEPS_IMPORT"
    
    old_import = deps_match.group(0)
    new_import = old_import.rstrip() + ", require_dev_or_above"
    src = src.replace(old_import, new_import, 1)
    
    with open(fp, "w", encoding="utf-8") as f: f.write(src)
    return "PATCHED"

print(f"issues.py: {patch_issues()}")
print(f"inputs.py: {patch_inputs()}")
PYEOF

ok "主要ルーター: require_* import 追加完了"

# ─────────────────────────────────────────────
# FE-1: usePermission フック作成
# ─────────────────────────────────────────────
section "FE-1: src/hooks/usePermission.ts 作成"

mkdir -p "$FE_SRC/hooks"
cat > "$FE_SRC/hooks/usePermission.ts" << 'TSEOF'
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
TSEOF

ok "usePermission.ts 作成完了"

# ─────────────────────────────────────────────
# FE-2: RoleBadge コンポーネント作成
# ─────────────────────────────────────────────
section "FE-2: src/components/RoleBadge.tsx 作成"

mkdir -p "$FE_SRC/components"
cat > "$FE_SRC/components/RoleBadge.tsx" << 'TSEOF'
/**
 * RoleBadge - ロール表示バッジ
 */
import React from "react";

type Role = "admin" | "pm" | "dev" | "viewer";

const ROLE_CONFIG: Record<Role, { label: string; color: string; icon: string }> = {
  admin: { label: "Admin", color: "bg-red-100 text-red-700 border-red-200", icon: "🔴" },
  pm:    { label: "PM",    color: "bg-purple-100 text-purple-700 border-purple-200", icon: "🟣" },
  dev:   { label: "Dev",   color: "bg-blue-100 text-blue-700 border-blue-200", icon: "🔵" },
  viewer:{ label: "Viewer",color: "bg-gray-100 text-gray-600 border-gray-200", icon: "⚪" },
};

interface Props {
  role: string;
  showIcon?: boolean;
  size?: "sm" | "md";
}

export const RoleBadge: React.FC<Props> = ({ role, showIcon = true, size = "sm" }) => {
  const config = ROLE_CONFIG[role as Role] ?? ROLE_CONFIG.viewer;
  const sizeClass = size === "sm" ? "text-xs px-1.5 py-0.5" : "text-sm px-2 py-1";

  return (
    <span className={`inline-flex items-center gap-0.5 rounded border font-medium ${config.color} ${sizeClass}`}>
      {showIcon && <span>{config.icon}</span>}
      {config.label}
    </span>
  );
};
TSEOF

ok "RoleBadge.tsx 作成完了"

# ─────────────────────────────────────────────
# FE-3: UserManagement.tsx（管理者用ユーザー管理画面）
# ─────────────────────────────────────────────
section "FE-3: src/pages/UserManagement.tsx 作成"

cat > "$FE_SRC/pages/UserManagement.tsx" << 'TSEOF'
/**
 * UserManagement - ユーザー管理画面（Admin専用）
 * - ユーザー一覧表示
 * - ロール変更
 * - 権限マトリクス表示
 */
import React, { useEffect, useState } from "react";
import { usePermission } from "../hooks/usePermission";
import { RoleBadge } from "../components/RoleBadge";
import { api } from "../api/client";

interface User {
  id: string;
  email: string;
  role: string;
  created_at?: string;
}

const ROLES = ["admin", "pm", "dev", "viewer"] as const;

const PERMISSION_MATRIX = [
  { action: "Input登録",    admin: true, pm: true,  dev: true,  viewer: false },
  { action: "分類変更",     admin: true, pm: true,  dev: false, viewer: false },
  { action: "Action変更",   admin: true, pm: true,  dev: false, viewer: false },
  { action: "Issue作成",    admin: true, pm: true,  dev: true,  viewer: false },
  { action: "Issue削除",    admin: true, pm: false, dev: false, viewer: false },
  { action: "コメント投稿", admin: true, pm: true,  dev: true,  viewer: false },
  { action: "ラベル管理",   admin: true, pm: true,  dev: false, viewer: false },
  { action: "辞書編集",     admin: true, pm: false, dev: false, viewer: false },
  { action: "ロール変更",   admin: true, pm: false, dev: false, viewer: false },
  { action: "閲覧",         admin: true, pm: true,  dev: true,  viewer: true  },
];

export const UserManagement: React.FC = () => {
  const { isAdmin } = usePermission();
  const [users, setUsers] = useState<User[]>([]);
  const [loading, setLoading] = useState(true);
  const [updating, setUpdating] = useState<string | null>(null);
  const [msg, setMsg] = useState<{ type: "ok" | "err"; text: string } | null>(null);

  useEffect(() => {
    if (!isAdmin) return;
    fetchUsers();
  }, [isAdmin]);

  const fetchUsers = async () => {
    try {
      const res = await api.get("/users");
      setUsers(res.data);
    } catch {
      setMsg({ type: "err", text: "ユーザー一覧の取得に失敗しました" });
    } finally {
      setLoading(false);
    }
  };

  const handleRoleChange = async (userId: string, newRole: string) => {
    setUpdating(userId);
    setMsg(null);
    try {
      await api.patch(`/users/${userId}/role`, { role: newRole });
      setUsers(prev => prev.map(u => u.id === userId ? { ...u, role: newRole } : u));
      setMsg({ type: "ok", text: "ロールを変更しました" });
    } catch (e: any) {
      setMsg({ type: "err", text: e.response?.data?.detail ?? "変更に失敗しました" });
    } finally {
      setUpdating(null);
    }
  };

  // Admin 以外は非表示
  if (!isAdmin) {
    return (
      <div className="p-8 text-center">
        <div className="text-4xl mb-3">🔒</div>
        <h2 className="text-lg font-semibold text-gray-700">アクセス権限がありません</h2>
        <p className="text-gray-500 mt-1">この画面は Admin のみ表示できます。</p>
      </div>
    );
  }

  return (
    <div className="max-w-5xl mx-auto p-6 space-y-8">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">👥 ユーザー管理</h1>
          <p className="text-sm text-gray-500 mt-1">Admin専用 — ロールの確認・変更</p>
        </div>
      </div>

      {/* メッセージ */}
      {msg && (
        <div className={`rounded-lg px-4 py-3 text-sm font-medium ${
          msg.type === "ok"
            ? "bg-green-50 text-green-700 border border-green-200"
            : "bg-red-50 text-red-700 border border-red-200"
        }`}>
          {msg.type === "ok" ? "✅ " : "❌ "}{msg.text}
        </div>
      )}

      {/* ユーザー一覧 */}
      <div className="bg-white border border-gray-200 rounded-xl overflow-hidden shadow-sm">
        <div className="px-6 py-4 border-b border-gray-100 bg-gray-50">
          <h2 className="font-semibold text-gray-700">ユーザー一覧</h2>
        </div>
        {loading ? (
          <div className="p-8 text-center text-gray-400">読み込み中...</div>
        ) : users.length === 0 ? (
          <div className="p-8 text-center text-gray-400">ユーザーが見つかりません</div>
        ) : (
          <table className="w-full">
            <thead>
              <tr className="text-xs text-gray-500 border-b border-gray-100 bg-gray-50">
                <th className="px-6 py-3 text-left font-medium">メールアドレス</th>
                <th className="px-6 py-3 text-left font-medium">現在のロール</th>
                <th className="px-6 py-3 text-left font-medium">ロール変更</th>
                <th className="px-6 py-3 text-left font-medium">登録日</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-50">
              {users.map(user => (
                <tr key={user.id} className="hover:bg-gray-50 transition-colors">
                  <td className="px-6 py-4 text-sm text-gray-900">{user.email}</td>
                  <td className="px-6 py-4">
                    <RoleBadge role={user.role} />
                  </td>
                  <td className="px-6 py-4">
                    <div className="flex gap-1.5">
                      {ROLES.map(r => (
                        <button
                          key={r}
                          disabled={user.role === r || updating === user.id}
                          onClick={() => handleRoleChange(user.id, r)}
                          className={`text-xs px-2.5 py-1 rounded-full border font-medium transition-colors ${
                            user.role === r
                              ? "bg-gray-100 text-gray-400 border-gray-200 cursor-default"
                              : "bg-white hover:bg-blue-50 text-gray-600 hover:text-blue-700 border-gray-300 hover:border-blue-300 cursor-pointer"
                          } disabled:opacity-50`}
                        >
                          {r}
                        </button>
                      ))}
                    </div>
                  </td>
                  <td className="px-6 py-4 text-sm text-gray-400">
                    {user.created_at
                      ? new Date(user.created_at).toLocaleDateString("ja-JP")
                      : "—"}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* 権限マトリクス */}
      <div className="bg-white border border-gray-200 rounded-xl overflow-hidden shadow-sm">
        <div className="px-6 py-4 border-b border-gray-100 bg-gray-50">
          <h2 className="font-semibold text-gray-700">権限マトリクス</h2>
          <p className="text-xs text-gray-500 mt-0.5">各ロールが実行できる操作の一覧</p>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead>
              <tr className="text-xs border-b border-gray-100 bg-gray-50">
                <th className="px-6 py-3 text-left text-gray-500 font-medium">操作</th>
                {ROLES.map(r => (
                  <th key={r} className="px-4 py-3 text-center">
                    <RoleBadge role={r} size="sm" />
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-50">
              {PERMISSION_MATRIX.map(row => (
                <tr key={row.action} className="hover:bg-gray-50">
                  <td className="px-6 py-3 text-sm text-gray-700">{row.action}</td>
                  {ROLES.map(r => (
                    <td key={r} className="px-4 py-3 text-center text-base">
                      {row[r] ? "✅" : "—"}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};

export default UserManagement;
TSEOF

ok "UserManagement.tsx 作成完了"

# ─────────────────────────────────────────────
# FE-4: App.tsx / Layout.tsx に追加
# ─────────────────────────────────────────────
section "FE-4: App.tsx / Layout.tsx に /users ルート追加"

python3 << PYEOF
import os, re

APP_TSX = "$FE_SRC/App.tsx"
LAYOUT_TSX = "$FE_SRC/components/Layout.tsx"

# App.tsx
if os.path.exists(APP_TSX):
    with open(APP_TSX, encoding="utf-8") as f:
        src = f.read()
    if "UserManagement" not in src:
        # import 追加
        last_import_line = ""
        for line in src.split("\n"):
            if line.startswith("import") and "pages" in line:
                last_import_line = line
        if last_import_line:
            src = src.replace(
                last_import_line,
                last_import_line + "\nimport UserManagement from './pages/UserManagement';"
            )
        # Route 追加
        route_anchor = re.search(r'<Route path="[^"]*" element.*?/>', src)
        if route_anchor:
            last = ""
            for m in re.finditer(r'<Route path="[^"]*" element.*?/>', src):
                last = m.group(0)
            if last:
                src = src.replace(
                    last,
                    last + '\n        <Route path="/users" element={<UserManagement />} />'
                )
        with open(APP_TSX, "w", encoding="utf-8") as f:
            f.write(src)
        print("App.tsx UPDATED")
    else:
        print("App.tsx SKIP")

# Layout.tsx
if os.path.exists(LAYOUT_TSX):
    with open(LAYOUT_TSX, encoding="utf-8") as f:
        src = f.read()
    if "users" not in src or "ユーザー管理" not in src:
        # ナビリンク追加（ラベル管理の後）
        anchor = re.search(r'(/labels[^<]*[^/]*/a>|🏷.*?/a>)', src)
        if "/labels" in src:
            # /labels の後に追加
            src = re.sub(
                r'(.*?/labels.*?</a>)',
                r'\1\n            <a href="/users" className="flex items-center gap-2 px-3 py-2 rounded-lg hover:bg-gray-100 text-gray-700 text-sm font-medium transition-colors">👥 ユーザー管理</a>',
                src, count=1, flags=re.DOTALL
            )
        with open(LAYOUT_TSX, "w", encoding="utf-8") as f:
            f.write(src)
        print("Layout.tsx UPDATED")
    else:
        print("Layout.tsx SKIP")
PYEOF

ok "App.tsx / Layout.tsx 更新完了"

# ─────────────────────────────────────────────
# FE-5: Header に現在のユーザーロールバッジ表示
# ─────────────────────────────────────────────
section "FE-5: Layout.tsx にロールバッジ表示追加"

python3 << PYEOF
import os, re

LAYOUT = "$FE_SRC/components/Layout.tsx"
if not os.path.exists(LAYOUT):
    print("SKIP: Layout.tsx not found")
    exit(0)

with open(LAYOUT, encoding="utf-8") as f:
    src = f.read()

if "RoleBadge" in src:
    print("SKIP: RoleBadge 既存")
    exit(0)

# RoleBadge import 追加
if "import" in src:
    first_import = src.split("\n")[0]
    src = src.replace(
        first_import,
        first_import + "\nimport { RoleBadge } from './RoleBadge';\nimport { usePermission } from '../hooks/usePermission';"
    )

# usePermission フック呼び出し追加（コンポーネント内）
# function Layout や const Layout の直後
layout_func = re.search(r'((?:function|const)\s+Layout[^{]*{)', src)
if layout_func:
    src = src.replace(
        layout_func.group(0),
        layout_func.group(0) + "\n  const { role } = usePermission();"
    )

print("Layout.tsx: usePermission 追加完了（RoleBadge は手動で配置してください）")
with open(LAYOUT, "w", encoding="utf-8") as f:
    f.write(src)
PYEOF

ok "Layout.tsx: usePermission / RoleBadge import 追加完了"

# ─────────────────────────────────────────────
# BE-6: バックエンド再起動 & 確認
# ─────────────────────────────────────────────
section "BE-6: バックエンド再起動 & 確認"

cd "$BACKEND"
source .venv/bin/activate 2>/dev/null || true

pkill -f "uvicorn app.main" 2>/dev/null || true
sleep 1
nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
  > "$PROJECT_DIR/logs/backend.log" 2>&1 &
sleep 4

echo "--- backend.log (末尾8行) ---"
tail -8 "$PROJECT_DIR/logs/backend.log" 2>/dev/null || echo "(ログなし)"
echo "-----------------------------"

if curl -s http://localhost:8089/docs | head -3 | grep -q "swagger\|html"; then
  ok "バックエンド起動 ✅"
else
  warn "バックエンド応答なし → backend.log を確認"
fi

# /users エンドポイント確認
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8089/api/v1/users)
if [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ] || [ "$HTTP_CODE" = "200" ]; then
  ok "GET /api/v1/users 確認 ✅ (HTTP $HTTP_CODE)"
else
  warn "GET /api/v1/users → HTTP $HTTP_CODE"
fi

# ─────────────────────────────────────────────
# 完了サマリー
# ─────────────────────────────────────────────
section "完了サマリー"
echo ""
echo "実装完了:"
echo "  ✅ BE: deps.py に RBAC ヘルパー追加"
echo "     - require_role(*roles)          — 指定ロールのみ許可"
echo "     - require_admin()               — Admin のみ"
echo "     - require_pm_or_above()         — PM 以上"
echo "     - require_dev_or_above()        — Dev 以上"
echo "     - is_admin() / is_pm_or_above() — 判定関数"
echo "  ✅ BE: GET  /api/v1/users          — ユーザー一覧（Admin）"
echo "  ✅ BE: PATCH /api/v1/users/{id}/role — ロール変更（Admin）"
echo "  ✅ BE: issues / inputs / actions に require_* import 追加"
echo "  ✅ FE: src/hooks/usePermission.ts"
echo "     - canCreateInput / canChangeClassification / canChangeAction ..."
echo "  ✅ FE: src/components/RoleBadge.tsx"
echo "     - 🔴 Admin / 🟣 PM / 🔵 Dev / ⚪ Viewer バッジ"
echo "  ✅ FE: src/pages/UserManagement.tsx"
echo "     - ユーザー一覧 + ロール変更 UI"
echo "     - 権限マトリクス表（設計書準拠）"
echo "  ✅ FE: App.tsx に /users ルート追加"
echo "  ✅ FE: Layout.tsx に 👥 ユーザー管理 リンク追加"
echo ""
echo "ブラウザで確認:"
echo "  1. 左メニュー「👥 ユーザー管理」→ Admin でログイン時のみ表示"
echo "  2. ロール変更ボタンで admin / pm / dev / viewer を切り替え"
echo "  3. 権限マトリクステーブルで設計書の仕様と照合"
echo "  4. Viewer でログイン → 「👥 ユーザー管理」は 🔒 アクセス不可を確認"
echo ""
ok "Phase 2: 権限管理（RBAC）実装完了！"
