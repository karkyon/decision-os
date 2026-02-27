#!/usr/bin/env bash
# 24_patch.sh - deps.py に RBAC 関数が実際に書き込まれているか確認・修正

set -euo pipefail
GREEN='\033[0;32m'; BOLD='\033[1m'; RESET='\033[0m'
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

DEPS="/home/karkyon/projects/decision-os/backend/app/core/deps.py"
PROJECT_DIR="$HOME/projects/decision-os"

section "deps.py 現状確認"
echo "--- deps.py 末尾20行 ---"
tail -20 "$DEPS"
echo "------------------------"

section "RBAC 関数を強制書き込み"

python3 << 'PYEOF'
path = "/home/karkyon/projects/decision-os/backend/app/core/deps.py"
with open(path, encoding="utf-8") as f:
    src = f.read()

# 既存の require_role ブロックを削除（再書き込みのため）
import re
src = re.sub(r'\n# ─+ RBAC ─+.*', '', src, flags=re.DOTALL)
src = src.rstrip()

rbac = '''

# ─── RBAC ヘルパー ───────────────────────────────────────────────────────────
ROLE_HIERARCHY = {"admin": 4, "pm": 3, "dev": 2, "viewer": 1}

def require_role(*allowed_roles: str):
    from fastapi import HTTPException, status
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

src = src + rbac
with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("書き込み完了")
PYEOF

ok "deps.py RBAC 関数 書き込み完了"

section "確認"
grep -n "def require_pm_or_above\|def require_dev_or_above\|def require_admin\|def require_role" "$DEPS"

section "バックエンド再起動"
cd "$PROJECT_DIR/backend"
source .venv/bin/activate 2>/dev/null || true

pkill -f "uvicorn app.main" 2>/dev/null || true
sleep 1
nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
  > "$PROJECT_DIR/logs/backend.log" 2>&1 &
sleep 4

echo "--- backend.log (末尾8行) ---"
tail -8 "$PROJECT_DIR/logs/backend.log"
echo "-----------------------------"

if curl -s http://localhost:8089/docs | head -3 | grep -q "swagger\|html"; then
  ok "バックエンド起動 ✅"
  # /users エンドポイント確認
  CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8089/api/v1/users)
  ok "GET /api/v1/users → HTTP $CODE"
else
  echo "バックエンドログ全文:"
  cat "$PROJECT_DIR/logs/backend.log"
fi
