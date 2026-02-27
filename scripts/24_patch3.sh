#!/usr/bin/env bash
set -euo pipefail
GREEN='\033[0;32m'; BOLD='\033[1m'; RESET='\033[0m'
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
API_PY="$PROJECT_DIR/backend/app/api/v1/api.py"
USERS_PY="$PROJECT_DIR/backend/app/api/v1/routers/users.py"

section "原因確認: users.py の router prefix"
head -5 "$USERS_PY"

section "api.py: users_router の prefix を修正"
# prefix="/api/v1" → prefix="" に変更（他のルーターと同じ形式に）
sed -i 's|api_router.include_router(users_router, prefix="/api/v1")|api_router.include_router(users_router)|' "$API_PY"
ok "prefix 修正完了"

section "users.py: router prefix 確認・修正"
python3 << 'PYEOF'
path = "/home/karkyon/projects/decision-os/backend/app/api/v1/routers/users.py"
with open(path, encoding="utf-8") as f:
    src = f.read()

# router の prefix を確認・修正
import re
# prefix="/users" がなければ追加
if 'prefix="/users"' not in src:
    src = src.replace(
        'router = APIRouter()',
        'router = APIRouter(prefix="/api/v1/users", tags=["users"])'
    )
    # すでに別のprefixがあれば修正
    src = re.sub(
        r'router = APIRouter\(prefix="[^"]*"',
        'router = APIRouter(prefix="/api/v1/users"',
        src
    )
    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
    print("FIXED: router prefix → /api/v1/users")
else:
    print("OK: prefix 既に設定済み")

# router prefix 確認
m = re.search(r'router = APIRouter\([^)]*\)', src)
print(f"router 定義: {m.group(0) if m else '見つからない'}")
PYEOF
ok "users.py 修正完了"

section "バックエンド再起動 & 確認"
cd "$PROJECT_DIR/backend"
source .venv/bin/activate 2>/dev/null || true
pkill -f "uvicorn app.main" 2>/dev/null || true; sleep 1
nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
  > "$PROJECT_DIR/logs/backend.log" 2>&1 &
sleep 4
tail -4 "$PROJECT_DIR/logs/backend.log"

if curl -s http://localhost:8089/docs | head -3 | grep -q "swagger\|html"; then
  ok "バックエンド起動 ✅"
  CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8089/api/v1/users)
  ok "GET /api/v1/users → HTTP $CODE"
  if [ "$CODE" = "401" ] || [ "$CODE" = "403" ] || [ "$CODE" = "200" ]; then
    ok "エンドポイント確認 ✅ (認証が必要なため $CODE は正常)"
  fi
else
  echo "起動失敗:"; cat "$PROJECT_DIR/logs/backend.log"
fi
