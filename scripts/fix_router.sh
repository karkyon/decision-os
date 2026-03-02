#!/bin/bash
# SSO/TOTP エンドポイント 404 修正
set -e

BACKEND="$HOME/projects/decision-os/backend"
GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()      { echo -e "${GREEN}✅ $1${NC}"; }
section() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

cd "$BACKEND"
source .venv/bin/activate

# ─────────────────────────────────────────────
# 1. 現状確認
# ─────────────────────────────────────────────
section "1. api.py 現在の内容"
cat -n app/api/v1/api.py

section "2. main.py 現在の内容"
cat -n app/main.py

section "3. routers/ ディレクトリ確認"
ls -la app/api/v1/routers/

# ─────────────────────────────────────────────
# 4. api.py を正しく修正
# ─────────────────────────────────────────────
section "4. api.py 修正"

python3 << 'PYEOF'
api_path = "app/api/v1/api.py"

with open(api_path, "r", encoding="utf-8") as f:
    src = f.read()

print("=== 現在の api.py ===")
print(src)
print("=" * 40)

# sso ルーターの import と include を正しく追加
import_line   = "from app.api.v1.routers import sso"
include_line  = 'api_router.include_router(sso.router)'

# 壊れた前回の追記を削除
import re
src = re.sub(r'from app\.api\.v1\.routers import sso.*\n', '', src)
src = re.sub(r'api_router\.include_router\(sso.*\n', '', src)
src = re.sub(r'from app\.api\.v1 import sso.*\n', '', src)

# import ブロックの末尾に追加
# "from app.api.v1.routers import" が含まれる最後の行の後に挿入
lines = src.splitlines()
last_import_idx = -1
for i, line in enumerate(lines):
    if line.startswith("from ") or line.startswith("import "):
        last_import_idx = i

if last_import_idx >= 0:
    lines.insert(last_import_idx + 1, import_line)
else:
    lines.insert(0, import_line)

# api_router の include_router 群の最後に追加
src2 = "\n".join(lines)

# include_router が存在する場合はその末尾に追加
if "include_router" in src2:
    # 最後の include_router の後に追加
    src2 = re.sub(
        r'(api_router\.include_router\([^)]+\)(?:\s*\n)*(?!api_router))',
        lambda m: m.group(0),
        src2
    )
    # シンプルに末尾に追加
    src2 = src2.rstrip() + f"\n{include_line}\n"
else:
    src2 = src2.rstrip() + f"\n\n{include_line}\n"

print("\n=== 修正後の api.py ===")
print(src2)

with open(api_path, "w", encoding="utf-8") as f:
    f.write(src2)
print("\napi.py 修正完了")
PYEOF

ok "api.py 修正完了"

section "4b. 修正後の api.py を確認"
cat -n app/api/v1/api.py

# ─────────────────────────────────────────────
# 5. インポートテスト
# ─────────────────────────────────────────────
section "5. インポートテスト"

python3 -c "
import sys
sys.path.insert(0, '.')
from app.api.v1.routers import sso
print('sso ルーター import ✅')
print('登録エンドポイント:')
for route in sso.router.routes:
    print(f'  {route.methods} {route.path}')
" && ok "SSO ルーター import 成功" || {
  echo "❌ import エラー。sso.py の内容を確認します:"
  cat app/api/v1/routers/sso.py | head -30
}

# ─────────────────────────────────────────────
# 6. main.py の router マウント確認
# ─────────────────────────────────────────────
section "6. main.py のルーターマウント確認・修正"

python3 << 'PYEOF'
main_path = "app/main.py"
with open(main_path, "r", encoding="utf-8") as f:
    src = f.read()

print("=== main.py ===")
print(src)
print("===============")

# api_router が app.include_router されているか確認
if "include_router" not in src:
    print("⚠️  main.py に include_router がありません → 追加します")
    import re
    # FastAPI app 定義の後に追加
    addition = """
from app.api.v1.api import api_router
app.include_router(api_router)
"""
    src = src.rstrip() + "\n" + addition
    with open(main_path, "w", encoding="utf-8") as f:
        f.write(src)
    print("main.py: include_router 追加完了")
else:
    print("✅ main.py に include_router あり")
PYEOF

# ─────────────────────────────────────────────
# 7. バックエンド再起動
# ─────────────────────────────────────────────
section "7. バックエンド再起動"

pkill -f "uvicorn app.main" 2>/dev/null || true
sleep 1
nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
  > "$HOME/projects/decision-os/logs/backend.log" 2>&1 &
sleep 5

echo "--- backend.log (末尾 15 行) ---"
tail -15 "$HOME/projects/decision-os/logs/backend.log"
echo "--------------------------------"

if ! curl -s http://localhost:8089/docs | head -3 | grep -q "swagger\|html"; then
  echo "❌ バックエンド起動失敗。ログ全文:"
  cat "$HOME/projects/decision-os/logs/backend.log"
  exit 1
fi
ok "バックエンド起動"

# ─────────────────────────────────────────────
# 8. 全ルート一覧を表示
# ─────────────────────────────────────────────
section "8. 登録済みルート確認"

python3 -c "
import sys
sys.path.insert(0, '.')
from app.main import app
sso_routes = [r for r in app.routes if hasattr(r, 'path') and ('google' in r.path or 'github' in r.path or 'totp' in r.path)]
if sso_routes:
    print('SSO/TOTP ルート:')
    for r in sso_routes:
        methods = getattr(r, 'methods', {'GET'})
        print(f'  {methods} {r.path}')
else:
    print('⚠️  SSO/TOTP ルートが見つかりません')
    print('全ルート:')
    for r in app.routes:
        if hasattr(r, 'path'):
            print(f'  {r.path}')
"

# ─────────────────────────────────────────────
# 9. エンドポイント HTTP 確認
# ─────────────────────────────────────────────
section "9. エンドポイント確認"

for path in "/api/v1/auth/google" "/api/v1/auth/github" "/api/v1/auth/totp/setup"; do
  HTTP=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8089${path}")
  if [[ "$HTTP" =~ ^(200|307|401|403|422)$ ]]; then
    ok "GET ${path} → HTTP ${HTTP} ✅"
  else
    echo "⚠️  GET ${path} → HTTP ${HTTP}"
  fi
done

# Swagger で確認
echo ""
echo "Swagger UI で全エンドポイントを確認:"
echo "  http://localhost:8089/docs"
