#!/usr/bin/env bash
set -euo pipefail
GREEN='\033[0;32m'; BOLD='\033[1m'; RESET='\033[0m'
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

DEPS="/home/karkyon/projects/decision-os/backend/app/core/deps.py"
API_PY="/home/karkyon/projects/decision-os/backend/app/api/v1/api.py"
PROJECT_DIR="$HOME/projects/decision-os"

section "deps.py: 重複 require_role を削除してクリーンに書き直し"
python3 << 'PYEOF'
import re
path = "/home/karkyon/projects/decision-os/backend/app/core/deps.py"
with open(path, encoding="utf-8") as f:
    src = f.read()

# require_role 以降を全部削除して書き直す
cut = src.find("\ndef require_role")
if cut == -1:
    cut = src.find("\n# ─── RBAC")
if cut != -1:
    src = src[:cut]

src = src.rstrip() + '''

# ─── RBAC ヘルパー ───────────────────────────────────────────────────────────
ROLE_HIERARCHY = {"admin": 4, "pm": 3, "dev": 2, "viewer": 1}

def require_role(*allowed_roles: str):
    """指定ロールのみ許可する Dependency"""
    def _checker(current_user: User = Depends(get_current_user)):
        if current_user.role not in allowed_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"この操作には {' または '.join(allowed_roles)} 権限が必要です（現在: {current_user.role}）"
            )
        return current_user
    return _checker

def require_admin():
    return require_role("admin")

def require_pm_or_above():
    return require_role("admin", "pm")

def require_dev_or_above():
    return require_role("admin", "pm", "dev")

def is_admin(user) -> bool:
    return getattr(user, "role", "") == "admin"

def is_pm_or_above(user) -> bool:
    return getattr(user, "role", "viewer") in ("admin", "pm")

def is_dev_or_above(user) -> bool:
    return getattr(user, "role", "viewer") in ("admin", "pm", "dev")
'''

with open(path, "w", encoding="utf-8") as f:
    f.write(src)

# 確認
with open(path, encoding="utf-8") as f:
    final = f.read()
count = final.count("def require_role")
print(f"require_role の定義数: {count} (1つであること)")
import re
funcs = re.findall(r'^def \w+', final, re.MULTILINE)
print("定義済み関数:", funcs)
PYEOF
ok "deps.py クリーン完了"

section "api.py: users_router の登録確認・修正"
python3 << 'PYEOF'
import re, os
path = "/home/karkyon/projects/decision-os/backend/app/api/v1/api.py"
with open(path, encoding="utf-8") as f:
    src = f.read()

print("--- api.py 現状 ---")
print(src)
print("-------------------")

changed = False

# users import がなければ追加
if "routers.users" not in src and "from .routers.users" not in src:
    # 最後の routers import の後に追加
    last = ""
    for line in src.split("\n"):
        if "from .routers" in line:
            last = line
    if last:
        src = src.replace(last, last + "\nfrom .routers.users import router as users_router")
        changed = True
        print("ADDED: users import")

# include_router がなければ追加
if "users_router" not in src:
    # 最後の include_router の後に追加
    lines = src.split("\n")
    last_idx = -1
    for i, line in enumerate(lines):
        if "include_router" in line:
            last_idx = i
    if last_idx >= 0:
        lines.insert(last_idx + 1, 'api_router.include_router(users_router, prefix="/api/v1", tags=["users"])')
        src = "\n".join(lines)
        changed = True
        print("ADDED: include_router users_router")
else:
    # prefix を修正（/api/v1 が二重になっていないか確認）
    if 'users_router, prefix="/api/v1"' in src and '/api/v1/api/v1' not in src:
        # prefix を修正 → users は prefix="" でOK（api_router 自体に /api/v1 がついている場合）
        # まず api_router の prefix を確認
        if 'APIRouter(prefix="/api/v1")' in src or "prefix='/api/v1'" in src:
            src = src.replace(
                'api_router.include_router(users_router, prefix="/api/v1")',
                'api_router.include_router(users_router)'
            )
            changed = True
            print("FIXED: users_router prefix 修正")
        print("users_router は既に登録済み")

if changed:
    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
    print("api.py 更新完了")
PYEOF
ok "api.py 確認完了"

section "api_router の prefix 確認"
python3 << 'PYEOF'
path = "/home/karkyon/projects/decision-os/backend/app/api/v1/api.py"
with open(path, encoding="utf-8") as f:
    src = f.read()
print(src)
PYEOF

section "バックエンド再起動"
cd "$PROJECT_DIR/backend"
source .venv/bin/activate 2>/dev/null || true
pkill -f "uvicorn app.main" 2>/dev/null || true; sleep 1
nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
  > "$PROJECT_DIR/logs/backend.log" 2>&1 &
sleep 4
tail -6 "$PROJECT_DIR/logs/backend.log"

if curl -s http://localhost:8089/docs | head -3 | grep -q "swagger\|html"; then
  ok "バックエンド起動 ✅"
  for PATH_TRY in "/api/v1/users" "/users"; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8089${PATH_TRY}")
    echo "  $PATH_TRY → HTTP $CODE"
  done
else
  echo "起動失敗:"
  cat "$PROJECT_DIR/logs/backend.log"
fi
